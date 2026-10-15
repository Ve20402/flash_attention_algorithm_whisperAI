#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/of_reserved_mem.h>
#include <linux/dmaengine.h>
#include <linux/dma-mapping.h>
#include <linux/gpio/consumer.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/mutex.h>
#include <linux/completion.h>
#include <linux/delay.h>
#include <linux/jiffies.h>

#include "fa_axis.h"

#define FA_DMA_CHUNK      (1024u * 1024u * 4)

#define FA_TX_TIMEOUT_MS  (60000u)

#define FA_RUN_TIMEOUT_MS (300000u)

struct fa_dev {
	struct device    *dev;
	struct dma_chan  *mm2s;
	struct dma_chan  *s2mm;
	struct gpio_desc *run;
	struct gpio_desc *done;

	void             *tx_cpu;
	dma_addr_t        tx_dma;
	void             *rx_cpu;
	dma_addr_t        rx_dma;

	struct mutex      lock;
	struct completion rx_done;
	struct completion tx_done;
	bool              running;
	int               dma_error;
	bool              have_rmem;

	struct miscdevice misc;
};

static void fa_rx_callback(void *arg, const struct dmaengine_result *res)
{
	struct fa_dev *fa = arg;

	if (res->result != DMA_TRANS_NOERROR)
		fa->dma_error = -EIO;
	complete(&fa->rx_done);
}

static void fa_tx_callback(void *arg, const struct dmaengine_result *res)
{
	struct fa_dev *fa = arg;

	if (res->result != DMA_TRANS_NOERROR)
		fa->dma_error = -EIO;
	complete(&fa->tx_done);
}

static int fa_run(struct fa_dev *fa)
{
	struct dma_slave_config cfg = {};
	struct dma_async_tx_descriptor *tx;
	struct scatterlist sg;
	size_t offset;
	long left;
	int ret = 0;

	if (fa->running)
		return -EBUSY;

	fa->running = true;
	fa->dma_error = 0;
	reinit_completion(&fa->rx_done);

	cfg.direction = DMA_DEV_TO_MEM;
	cfg.src_addr_width = DMA_SLAVE_BUSWIDTH_8_BYTES;
	cfg.dst_addr_width = DMA_SLAVE_BUSWIDTH_8_BYTES;
	dmaengine_slave_config(fa->s2mm, &cfg);

	cfg.direction = DMA_MEM_TO_DEV;
	cfg.src_addr_width = DMA_SLAVE_BUSWIDTH_4_BYTES;
	cfg.dst_addr_width = DMA_SLAVE_BUSWIDTH_4_BYTES;
	dmaengine_slave_config(fa->mm2s, &cfg);

	sg_init_table(&sg, 1);
	sg_dma_address(&sg) = fa->rx_dma;
	sg_dma_len(&sg) = FA_RX_SIZE;
	tx = dmaengine_prep_slave_sg(fa->s2mm, &sg, 1, DMA_DEV_TO_MEM,
				     DMA_PREP_INTERRUPT);
	if (!tx) {
		ret = -EIO;
		goto out;
	}
	tx->callback_result = fa_rx_callback;
	tx->callback_param = fa;
	dmaengine_submit(tx);
	dma_async_issue_pending(fa->s2mm);

	mb();

	gpiod_set_value(fa->run, 1);
	udelay(1);
	gpiod_set_value(fa->run, 0);

	for (offset = 0; offset < FA_TX_SIZE; offset += FA_DMA_CHUNK) {
		size_t len = min_t(size_t, FA_DMA_CHUNK, FA_TX_SIZE - offset);

		reinit_completion(&fa->tx_done);
		sg_init_table(&sg, 1);
		sg_dma_address(&sg) = fa->tx_dma + offset;
		sg_dma_len(&sg) = len;
		tx = dmaengine_prep_slave_sg(fa->mm2s, &sg, 1, DMA_MEM_TO_DEV,
					     DMA_PREP_INTERRUPT);
		if (!tx) {
			ret = -EIO;
			goto terminate;
		}
		tx->callback_result = fa_tx_callback;
		tx->callback_param = fa;
		dmaengine_submit(tx);
		dma_async_issue_pending(fa->mm2s);

		left = wait_for_completion_interruptible_timeout(
			&fa->tx_done, msecs_to_jiffies(FA_TX_TIMEOUT_MS));
		if (left == 0) {
			dev_err(fa->dev, "MM2S timed out at offset %zu\n", offset);
			ret = -ETIMEDOUT;
			goto terminate;
		}
		if (left < 0) {
			ret = left;
			goto terminate;
		}
		if (fa->dma_error) {
			ret = fa->dma_error;
			goto terminate;
		}

		if (gpiod_get_value(fa->done)) {
			dev_info(fa->dev, "engine all_done after %zu bytes\n",
				 offset + len);
			dmaengine_terminate_sync(fa->mm2s);
			break;
		}
	}

	left = wait_for_completion_interruptible_timeout(
		&fa->rx_done, msecs_to_jiffies(FA_RUN_TIMEOUT_MS));

	if (left == 0) {
		dev_err(fa->dev, "S2MM timed out\n");
		ret = -ETIMEDOUT;
		goto terminate;
	}
	if (left < 0) {
		ret = left;
		goto terminate;
	}

	ret = fa->dma_error;
	if (ret == 0 && !gpiod_get_value(fa->done))
		dev_warn(fa->dev, "S2MM complete but all_done is low\n");
	goto out;

terminate:
	dmaengine_terminate_sync(fa->mm2s);
	dmaengine_terminate_sync(fa->s2mm);
out:
	fa->running = false;
	return ret;
}

static int fa_open(struct inode *inode, struct file *file)
{
	struct miscdevice *m = file->private_data;

	file->private_data = container_of(m, struct fa_dev, misc);
	return 0;
}

static int fa_mmap(struct file *file, struct vm_area_struct *vma)
{
	struct fa_dev *fa = file->private_data;

	unsigned long sel = vma->vm_pgoff;

	size_t len = vma->vm_end - vma->vm_start;

	void *cpu;
	dma_addr_t dma;
	size_t size;

	int ret;

	if (sel == FA_MMAP_TX) {
		cpu = fa->tx_cpu;
		dma = fa->tx_dma;
		size = FA_TX_SIZE;
	} else if (sel == FA_MMAP_RX) {
		cpu = fa->rx_cpu;
		dma = fa->rx_dma;
		size = FA_RX_SIZE;
	} else {
		return -EINVAL;
	}

	if (len != size)
		return -EINVAL;

	mutex_lock(&fa->lock);
	vma->vm_pgoff = 0;
	ret = dma_mmap_attrs(fa->dev, vma, cpu, dma, size,
			     (sel == FA_MMAP_TX) ? DMA_ATTR_WRITE_COMBINE : 0);
	mutex_unlock(&fa->lock);

	return ret;
}

static long fa_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
	struct fa_dev *fa = file->private_data;
	void __user *uarg = (void __user *)arg;

	switch (cmd) {

		case FA_IOC_GET_INFO: {
			struct fa_info info = {
				.tx_size = FA_TX_SIZE,
				.rx_size = FA_RX_SIZE,
				.input_words = FA_INPUT_WORDS,
				.output_words = FA_OUTPUT_WORDS,
			};

			if (copy_to_user(uarg, &info, sizeof(info)))
				return -EFAULT;
			return 0;
		}

		case FA_IOC_RUN: {

			if (mutex_lock_interruptible(&fa->lock))
				return -ERESTARTSYS;

			long ret = fa_run(fa);

			mutex_unlock(&fa->lock);
			return ret;
		}
		default:
			return -ENOTTY;
	}
}

static const struct file_operations fa_fops = {
	.owner = THIS_MODULE,
	.open = fa_open,
	.mmap = fa_mmap,
	.unlocked_ioctl = fa_ioctl,
};

static int fa_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct fa_dev *fa;
	int ret;

	fa = devm_kzalloc(dev, sizeof(*fa), GFP_KERNEL);
	if (!fa)
		return -ENOMEM;

	fa->dev = dev;

	mutex_init(&fa->lock);
	init_completion(&fa->rx_done);
	init_completion(&fa->tx_done);

	platform_set_drvdata(pdev, fa);

	ret = of_reserved_mem_device_init(dev);
	if (ret && ret != -ENODEV)
		dev_warn(dev, "no reserved-memory pool (%d), using global CMA\n",
			 ret);
	else if (ret == 0)
		fa->have_rmem = true;

	fa->run = devm_gpiod_get(dev, "run", GPIOD_OUT_LOW);
	if (IS_ERR(fa->run))
		return dev_err_probe(dev, PTR_ERR(fa->run), "run gpio not found\n");

	fa->done = devm_gpiod_get(dev, "done", GPIOD_IN);
	if (IS_ERR(fa->done))
		return dev_err_probe(dev, PTR_ERR(fa->done), "done gpio not found\n");

	fa->mm2s = dma_request_chan(dev, "mm2s");
	if (IS_ERR(fa->mm2s))
		return dev_err_probe(dev, PTR_ERR(fa->mm2s), "mm2s channel not found\n");

	fa->s2mm = dma_request_chan(dev, "s2mm");
	if (IS_ERR(fa->s2mm)) {
		ret = PTR_ERR(fa->s2mm);
		goto err_mm2s;
	}

	fa->tx_cpu = dma_alloc_attrs(dev, FA_TX_SIZE, &fa->tx_dma, GFP_KERNEL,
				     DMA_ATTR_WRITE_COMBINE);
	if (!fa->tx_cpu) {
		dev_err(dev, "TX coherent alloc of %u bytes failed, enlarge CMA\n",
			FA_TX_SIZE);
		ret = -ENOMEM;
		goto err_s2mm;
	}

	fa->rx_cpu = dma_alloc_coherent(dev, FA_RX_SIZE, &fa->rx_dma, GFP_KERNEL);
	if (!fa->rx_cpu) {
		ret = -ENOMEM;
		goto err_tx;
	}

	fa->misc.minor = MISC_DYNAMIC_MINOR;
	fa->misc.name = "fa_axis";
	fa->misc.fops = &fa_fops;
	fa->misc.parent = dev;
	ret = misc_register(&fa->misc);
	if (ret)
		goto err_rx;

	dev_info(dev, "fa_axis ready: tx=%u bytes rx=%u bytes\n",
		 FA_TX_SIZE, FA_RX_SIZE);
	return 0;

err_rx:
	dma_free_coherent(dev, FA_RX_SIZE, fa->rx_cpu, fa->rx_dma);
err_tx:
	dma_free_attrs(dev, FA_TX_SIZE, fa->tx_cpu, fa->tx_dma, DMA_ATTR_WRITE_COMBINE);
err_s2mm:
	dma_release_channel(fa->s2mm);
err_mm2s:
	dma_release_channel(fa->mm2s);

	if (fa->have_rmem)
		of_reserved_mem_device_release(dev);
	return ret;
}

static void fa_remove(struct platform_device *pdev)
{
	struct fa_dev *fa = platform_get_drvdata(pdev);

	misc_deregister(&fa->misc);
	dmaengine_terminate_sync(fa->mm2s);
	dmaengine_terminate_sync(fa->s2mm);
	dma_free_coherent(fa->dev, FA_RX_SIZE, fa->rx_cpu, fa->rx_dma);
	dma_free_attrs(fa->dev, FA_TX_SIZE, fa->tx_cpu, fa->tx_dma, DMA_ATTR_WRITE_COMBINE);
	dma_release_channel(fa->s2mm);
	dma_release_channel(fa->mm2s);
	if (fa->have_rmem)
		of_reserved_mem_device_release(fa->dev);
}

static const struct of_device_id fa_of_match[] = {
	{ .compatible = "ee,fa-1.0" },
	{}
};
MODULE_DEVICE_TABLE(of, fa_of_match);

static struct platform_driver fa_driver = {
	.probe = fa_probe,
	.remove = fa_remove,
	.driver = {
		.name = "fa-axis",
		.of_match_table = fa_of_match,
	},
};
module_platform_driver(fa_driver);

MODULE_AUTHOR("Veljko Veselinovic EE103/2021 + Nikola Pavlica EE240/2021");
MODULE_DESCRIPTION("FlashAttention AXI-Stream accelerator driver");
MODULE_LICENSE("GPL");
