# Here! Try some Beetle Pi: Up and running with TigerBeetle on a Raspberry PI 4

> or is it raspberry-beetle... or tiger-pie?

## Background

In the TigerTeam's recent presentation on [Zig Showtime](https://www.youtube.com/watch?v=BH2jvJ74npM), 
someone (maybe Don?) mentioned that it would be interesting to see how TigerBeetle performed on 
cheap commodity hardware such as the Raspberry PI.

This certainly piqued my interest, as in my work with Mojaloop, one of our goals is to
make the cost of low-value transfers really cheap, which can only happen when the technology
costs of the platform (among other things) are also incredibly cheap. By extension, this will then
make it cheaper for Banks and Mobile Money Providers to serve their customers, and include an entire
new population of unbanked people into the digital economy.


So I ordered myself 2 (now tax deductible) Raspberry PIs, memory cards and cases and got to work.

_"This can't be too hard, can it?"_ I thought to myself, and well, no it really wasn't.

So here's my first writeup of my first experience getting TigerBeetle up and running on a Raspberry PI,
with a look at the different benchmark numbers to start to answer the following questions:

- What's the performance profile of TigerBeetle on a single Raspberry PI? How about a cluster of PIs?
- Where do we start hitting bottlenecks?
- Could we run Mojaloop on a cluster of Raspberry PIs using TigerBeetle as the clearing database? 
  What kind of performance might we be able to squeeze out of such a set up?
- Does this make sense in anything other than a toy example? Could someone use this hardware for a dev
  environment at least? How about in production? Am I crazy to imagine using RPIs and TigerBeetle in Production?

## Prerequisites

- **Raspberry Pis** - I ran through these steps and benchmarks with a Raspberry PI v4, with 8GB of RAM
- **MicroSD** - It turns out that PIs don't have any onboard storage, everything is MicroSD based. I ended up with a 
- **Power Supply** - Apparently you need a proper power supply for the PI if you want to get proper performance out of it, especially once you start connecting peripherals. I got the official Raspberry PI 3 Amp power supply, and it seems to work fine.




## Part 1: Install Ubuntu Server and TigerBeetle

I decided to use Ubuntu Server `21.04` on my PI, since I'm more familiar with Ubuntu, and I didn't need anything fancy such as a desktop environment. I also figured Zig and TigerBeetle would work easier out of the box with Ubuntu.

I simply followed [this guide](https://ubuntu.com/tutorials/how-to-install-ubuntu-on-your-raspberry-pi#1-overview) to install Ubuntu Server, and after messing up a few config options and fixing them, I could sign in to my PI over my local wifi!

```bash
$ ssh ubuntu@192.168.0 125
ubuntu@192.168.0.125's password:
Welcome to Ubuntu 21.04 (GNU/Linux 5.11.0-1015-raspi aarch64)
```

We're in! I spent more time mistyping the wifi password than anything else here.


Then it's time to check that we're using the right linux kernel so we can support `io_uring`:
```bash
$ uname -r
5.11.0-1015-raspi
```
5.11 > 5.7, so it looks good to me! 


Once I managed to ssh into the PI, I simply cloned the TigerBeetle repo, and checked out the `beta2` branch:

```bash
git clone https://github.com/coilhq/tigerbeetle.git
cd tigerbeetle
checkout beta2
```

From there, I just ran this install script, and everything just ... worked.

```bash
./scripts/install.sh

$ ./scripts/install.sh
Installing Zig 0.8.0 release build...
Downloading https://ziglang.org/download/0.8.0/zig-linux-aarch64-0.8.0.tar.xz...
...

...
Building TigerBeetle...

```


## Part 2: Waking the Tiger...Beetle

Before running the benchmarks, I thought I'd just try and run TigerBeetle manually to get a feel for the commands:

```bash
# Initialize a new cluster and run with one replica
$ mkdir -p /tmp/tigerbeetle

$ ./tigerbeetle init --directory=/tmp/tigerbeetle --cluster=0 --replica=0
info(storage): creating "cluster_0000000000_replica_000.tigerbeetle"...
info(storage): allocating 256MiB...
info: initialized data file

$ ./tigerbeetle start --directory=/tmp/tigerbeetle --cluster=0 --addresses=0.0.0.0:3001 --replica=0 > /tmp/tigerbeetle.log 2>&1 &


# check it didn't exit straight away:
$ ps aux | grep tiger
ubuntu     15066 28.5  6.6 1249424 532988 pts/0  SL   02:06   0:01 ./tigerbeetle start --directory=/tmp/tigerbeetle --cluster=1 --addresses=0.0.0.0:3001 --replica=0


# Send some commands using the demo scripts
$ zig/zig run -OReleaseSafe src/demo_01_create_accounts.zig
OK

$ zig/zig run -OReleaseSafe src/demo_02_lookup_accounts.zig
Account{ .id = 1, .user_data = 0, .reserved = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, .unit = 710, .code = 1000, .flags = AccountFlags{ .linked = false, .debits_must_not_exceed_credits = true, .credits_must_not_exceed_debits = false, .padding = 0 }, .debits_reserved = 0, .debits_accepted = 0, .credits_reserved = 0, .credits_accepted = 10000, .timestamp = 1630635597134784316 }
Account{ .id = 2, .user_data = 0, .reserved = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, .unit = 710, .code = 2000, .flags = AccountFlags{ .linked = false, .debits_must_not_exceed_credits = false, .credits_must_not_exceed_debits = false, .padding = 0 }, .debits_reserved = 0, .debits_accepted = 0, .credits_reserved = 0, .credits_accepted = 0, .timestamp = 1630635597134784317 }

```

It looks like it worked! At the very least, I managed to run a single replica of TigerBeetle, create a couple demo accounts and then look them up. I know there's more to the demo, but I'd rather get on to the benchmarks.

```bash
# Stop the server and clear the data
killall tigerbeetle
rm -rf /tmp/tigerbeetle
```

## Part 3: Running the Benchmarks

The main benchmark does the following:
1. inits and starts a single tigerbeetle replica
2. creates 2 accounts
3. sends through 1 million transfers in batches of 10,000, and times how long those transfers take

```bash
scripts/benchmark.sh
```

And the results:
```
Initializing replica 0...
Starting replica 0...

Benchmarking...
creating accounts...
batching transfers...
starting benchmark...
============================================
96918 transfers per second

create_transfers max p100 latency per 10,000 transfers = 198ms
commit_transfers max p100 latency per 10,000 transfers = 0ms

Stopping replica 0...
```

96,918 transfers per second! That's not bad at all for about $100 of hardware.

I ran the benchmark a few more times to average out the results:

| Run | TPS |
|---|---|
| 1 | 96918 |
| 2 | 94759 |
| 3 | 92764 |
| average: | 94814 |


After the main benchmark, I ran a few others:

### io_uring vs blocking filesystem calls:

This benchmark demonstrates the difference between using blocking IO to read and write to the filesystem vs io_uring.

```
$ zig/zig run demos/io_uring/fs_io_uring.zig

fs io_uring: write(4096)/fsync/read(4096) * 65536 pages = 386 syscalls: 50337ms
fs io_uring: write(4096)/fsync/read(4096) * 65536 pages = 386 syscalls: 47867ms
fs io_uring: write(4096)/fsync/read(4096) * 65536 pages = 386 syscalls: 48228ms
fs io_uring: write(4096)/fsync/read(4096) * 65536 pages = 386 syscalls: 47014ms
fs io_uring: write(4096)/fsync/read(4096) * 65536 pages = 386 syscalls: 46912ms


$ zig/zig run demos/io_uring/fs_blocking.zig
fs blocking: write(4096)/fsync/read(4096) * 65536 pages = 196608 syscalls: 332683ms
fs blocking: write(4096)/fsync/read(4096) * 65536 pages = 196608 syscalls: 233802ms
fs blocking: write(4096)/fsync/read(4096) * 65536 pages = 196608 syscalls: 209034ms
fs blocking: write(4096)/fsync/read(4096) * 65536 pages = 196608 syscalls: 206245ms
fs blocking: write(4096)/fsync/read(4096) * 65536 pages = 196608 syscalls: 207356ms
```

I think it's pretty clear that `io_uring` is the winner here.

### Node Hash Table implementation vs zig

This benchmark shows the speed difference of `@ronomon/hash-table` and Zig's std HashMap

```
$ node benchmark.js
1000000 hash table insertions in 4695ms
1000000 hash table insertions in 1388ms
1000000 hash table insertions in 1249ms
1000000 hash table insertions in 1235ms
1000000 hash table insertions in 1274ms

$ zig/zig run demos/hash_table/benchmark.zig
1000000 hash table insertions in 1501ms
1000000 hash table insertions in 1521ms
1000000 hash table insertions in 1537ms
1000000 hash table insertions in 1577ms
1000000 hash table insertions in 1638ms
```

Zig's performance here doesn't look as impressive as what we've seen elsewhere, such as in the [docs](https://github.com/coilhq/tigerbeetle/tree/main/demos/hash_table):


>Node.js
>
>On a 2020 MacBook Air 1,1 GHz Quad-Core Intel Core i5, Node.js can insert 2.4 million transfers per second:
>
>$ npm install --no-save @ronomon/hash-table
>$ node benchmark.js
>1000000 hash table insertions in 1004ms // V8 optimizing...
>1000000 hash table insertions in 468ms
>1000000 hash table insertions in 432ms
>1000000 hash table insertions in 427ms
>1000000 hash table insertions in 445ms
>
>Zig
>
>On the same development machine, not a production server, Zig's std lib HashMap can insert 12.6 million transfers per second:
>
>$ zig run benchmark.zig -O ReleaseSafe
>1000000 hash table insertions in 90ms
>1000000 hash table insertions in 79ms
>1000000 hash table insertions in 82ms
>1000000 hash table insertions in 89ms
>1000000 hash table insertions in 100ms

From my understanding of how the HashMap works, we could be hitting a performance bottleneck with the PI's SD Card storage, which is rather slow.

### Networking

To test the networking of the PI, we also install rust_echo_bench

```bash
$ zig/zig run demos/io_uring/net_io_uring.zig

# in another session - install rust_echo_bench
$ cd ~/
$ git clone https://github.com/haraldh/rust_echo_bench.git
$ cd rust_echo_bench

# 1 connection
$ cargo run --release -- --address "localhost:3001" --number 1 --duration 20 --length 64

Benchmarking: localhost:3001
1 clients, running 64 bytes, 20 sec.

Speed: 9905 request/sec, 9905 response/sec
Requests: 198112
Responses: 198111

# 2 connections
$ cargo run --release -- --address "localhost:3001" --number 2 --duration 20 --length 64

Benchmarking: localhost:3001
2 clients, running 64 bytes, 20 sec.

Speed: 19695 request/sec, 19695 response/sec
Requests: 393900
Responses: 393900

# 50 connections
$ cargo run --release -- --address "localhost:3001" --number 50 --duration 20 --length 64

Benchmarking: localhost:3001
50 clients, running 64 bytes, 20 sec.

Speed: 26735 request/sec, 26735 response/sec
Requests: 534715
Responses: 534714
```

## Next Steps

Thanks for reading! I'm hoping this will be a good starting point for discussion on running TigerBeetle on cheap hardware, and I welcome any comments or analysis on the benchmark results!

Next up for me with this little investigation is to run multiple TB replicas across 2 or more Raspberry PIs, and see how the performance profile changes as we add more resiliency.

> Thanks to Joran and the TigerTeam for inspiring me to learn about this!