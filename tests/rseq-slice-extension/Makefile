# SPDX-License-Identifier: GPL-2.0+
# Makefile for RSEQ Time Slice Extension Tests

CC = gcc
CFLAGS = -Wall -Wextra -O2 -pthread
LDFLAGS = -pthread

# RSEQ signature - architecture specific
ARCH := $(shell uname -m)
ifeq ($(ARCH),x86_64)
    CFLAGS += -DRSEQ_SIG=0x53053053
else ifeq ($(ARCH),i386)
    CFLAGS += -DRSEQ_SIG=0x53053053
else ifeq ($(ARCH),aarch64)
    CFLAGS += -DRSEQ_SIG=0xd428bc00
else ifeq ($(ARCH),arm)
    CFLAGS += -DRSEQ_SIG=0xe7f5def1
else
    $(error Unsupported architecture: $(ARCH))
endif

TARGETS = test_rseq_slice test_rseq_simple test_feature_check test_force_grant test_synthetic_workload test_debug_state

all: $(TARGETS)

test_rseq_slice: test_rseq_slice.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

test_rseq_simple: test_rseq_simple.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

test_feature_check: test_feature_check.c
	$(CC) $(CFLAGS) -o $@ $<

test_force_grant: test_force_grant.c
	$(CC) $(CFLAGS) -o $@ $<

test_synthetic_workload: test_synthetic_workload.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

test_debug_state: test_debug_state.c
	$(CC) $(CFLAGS) -o $@ $<

test: test_rseq_slice
	@echo "Running RSEQ Time Slice Extension tests..."
	@./test_rseq_slice

clean:
	rm -f $(TARGETS) *.o

.PHONY: all test clean
