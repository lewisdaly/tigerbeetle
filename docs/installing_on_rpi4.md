# Installing TigerBeetle on a Rasberry PI 4


> Not sure if this doc will stay here, I just want to keep notes as I go!


## Background

## Prerequisites
- Raspberry Pi - I'm using v4 with 8gb ram and a 32gb SD card


## Part 1: Setup RPI and run the benchmark locally

- Install Ubuntu Server on the RPI, using [this guide](https://ubuntu.com/tutorials/how-to-install-ubuntu-on-your-raspberry-pi#1-overview)


```
# network-config
version: 2
ethernets:
  eth0:
    dhcp4: true
    optional: true
wifis:
  wlan0:
    dhcp4: true
    addresses:
      - 192.168.0.111/24
    gateway4: 192.168.0.1
    nameservers:
      addresses: [ 8.8.8.8 ]
    optional: true
    access-points:
      "SSID":
        password: "password"
```

> Note:
> If you got these setting wrong, you can look at the cloud-init logs here: /var/log/cloud-init*
> And modify the network file here: /etc/cloud-init/???

```bash
# install arp (I'm on arch)
sudo pacman -S net-tools         
arp -na | grep -i "dc:a6:32"

# ? (192.168.0.125) at dc:a6:32:ea:73:75 [ether] on wlp5s0

# Log into the rpi!
ssh ubuntu@192.168.0.125
sudo apt-get update

uname -r
# 5.11.0-1007-raspi

cd ~/
git clone -b beta2 https://github.com/coilhq/tigerbeetle.git
cd tigerbeetle
# double check the branch
git branch

# Let's just try the plain install!
./scripts/install.sh

# and the benchmark?
./scripts/benchmark.sh

```

Looks like there are some issues with the benchmark:
```
Initializing replica 0...
Starting replica 0...

Benchmarking...
./src/benchmark.zig:82:10: error: expected type 'u8', found '*message_bus.MessageBusImpl(message_bus.ProcessType.client)'
        &message_bus,
         ^
./zig/lib/std/start.zig:458:40: note: referenced here
            const result = root.main() catch |err| {
                                       ^

Error running benchmark, here are more details (from benchmark.log):

info(storage): opening "cluster_0000000001_replica_000.tigerbeetle"...
debug(vr): 0: journal: size=256MiB headers_len=16384 headers=2MiB circular_buffer=252MiB
debug(vr): 0: init: client_table.capacity()=64 for config.clients_max=32 entries
debug(vr): 0: init: leader
debug(vr): 0: ping_timeout started
debug(vr): 0: commit_timeout started
debug(vr): 0: repair_timeout started
info: cluster=1 replica=0: listening on 127.0.0.1:3001
debug(vr): 0: repair_timeout fired
debug(vr): 0: repair_timeout reset
Stopping replica 0...
```


Maybe we can just switch to running tb off of the `main` branch:


```bash
git checkout main
./scripts/benchmark.sh

# Seems to work!
```

## Part 2: Run TB on the RPI, and the benchmark from a different machine


<!-- TODO: update to new `init` and `start` commands once we switch to beta2 branch -->
```bash
# on rpi

# back to beta2 branch
git checkout beta2

# build tb
zig/zig build -Drelease-safe
mv zig-out/bin/tigerbeetle .


# First try with 1 replica
mkdir -p /tmp/tigerbeetle

DIRECTORY="--directory=/tmp/tigerbeetle"
./tigerbeetle init ${DIRECTORY} --cluster=1 --replica=0
./tigerbeetle start ${DIRECTORY} --cluster=1 --addresses=0.0.0.0:3001 --replica=0



# now try with 3 replicas
mkdir -p /tmp/tigerbeetle

DIRECTORY="--directory=/tmp/tigerbeetle"
ADDRESSES="--addresses=0.0.0.0:3001,0.0.0.0:3002,0.0.0.0:3003"
./tigerbeetle init ${DIRECTORY} --cluster=0 --replica=0 > benchmark.log 2>&1
./tigerbeetle init ${DIRECTORY} --cluster=0 --replica=1 > benchmark.log 2>&1
./tigerbeetle init ${DIRECTORY} --cluster=0 --replica=2 > benchmark.log 2>&1


# start 3 replicas
./tigerbeetle start ${DIRECTORY} --cluster=0 ${ADDRESSES} --replica=0 > benchmark.log 2>&1 &
./tigerbeetle start ${DIRECTORY} --cluster=0 ${ADDRESSES} --replica=1 > benchmark.log 2>&1 &
./tigerbeetle start ${DIRECTORY} --cluster=0 ${ADDRESSES} --replica=2 > benchmark.log 2>&1 &


# see if they are running:
ps aux | grep tiger

# check the logs for good measure
tail benchmark.log 


# on client machine (in my case linux box)

# Change lines in ./src/demo.zig to point to our rpi:

# const cluster_id: u32 = 1; 
# var addresses = [_]std.net.Address{try std.net.Address.parseIp4("192.168.0.125", config.port)};
zig/zig run -OReleaseSafe src/demo_01_create_accounts.zig 




# Cleanup

# stop tigerbeetles
sudo killall tigerbeetle
rm -rf benchmark.log
rm -rf /tmp/tigerbeetle
```




### Part 3 Further benchmarks

```bash
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

# node hash table benchmark
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


# network benchmarks
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


## TODOs:
- easier config for demos
- is there a better way to expose tigerbeetle than binding to 0.0.0.0? The warning in `config.zig` is scary...
