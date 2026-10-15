KERNEL_SRC ?= /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)
CC ?= gcc

.PHONY: all modules clean

all: modules

modules:
	$(MAKE) -C $(KERNEL_SRC) M=$(PWD) modules

clean:
	$(MAKE) -C $(KERNEL_SRC) M=$(PWD) clean
