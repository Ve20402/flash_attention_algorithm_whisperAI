CC ?= gcc

.PHONY: all fa_test clean

all: fa_test

fa_test: fa_test.c ../../driver/fa_axis.h
	$(CC) -O2 -Wall -Wextra -o $@ fa_test.c -I../../driver/

clean:
	rm -f fa_test
