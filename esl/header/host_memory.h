#ifndef HOST_MEMORY_H
#define HOST_MEMORY_H

#include <cstdint>
#include <cstring>

class HostMemory {
  public:
	unsigned char *data;
	uint64_t size;

	HostMemory(uint64_t size_bytes) : size(size_bytes) {
		data = new unsigned char[size];
		std::memset(data, 0, size);
	}

	~HostMemory() { delete[] data; }

	void write(uint64_t addr, const unsigned char *src, uint64_t len) {
		if (addr + len <= size)
			std::memcpy(&data[addr], src, len);
	}

	void read(uint64_t addr, unsigned char *dst, uint64_t len) const {
		if (addr + len <= size)
			std::memcpy(dst, &data[addr], len);
	}
};

#endif
