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
```

## Part 2: Run TB on the RPI, and the benchmark from a different machine


<!-- TODO: update to new `init` and `start` commands once we switch to beta2 branch -->
```bash
# on rpi
CLUSTER_ID="--cluster-id=0a5ca1ab1ebee11e"
REPLICA_ADDRESSES="--replica-addresses=3001"
./tigerbeetle --cluster-id=1 --replica-addresses=0.0.0.0:3001,0.0.0.0:3002,0.0.0.0:3003 --replica-index=0 > benchmark.log 2>&1 &
./tigerbeetle --cluster-id=1 --replica-addresses=0.0.0.0:3001,0.0.0.0:3002,0.0.0.0:3003 --replica-index=1 > benchmark.log 2>&1 &
./tigerbeetle --cluster-id=1 --replica-addresses=0.0.0.0:3001,0.0.0.0:3002,0.0.0.0:3003 --replica-index=2 > benchmark.log 2>&1 &

# see if they are running:
ps aux | grep tiger

# check the logs for good measure
tail benchmark.logs


# on client machine (in my case linux box)
# TODO: how to configure the IP?


# Change line in ./src/demo.zig to point to our rpi:
# var addresses = [_]std.net.Address{try std.net.Address.parseIp4("192.168.0.125", config.port)};

zig/zig run -OReleaseSafe src/demo_01_create_accounts.zig 





# Cleanup

# stop tigerbeetles
sudo killall tigerbeetle
```





## TODOs:
- easier config for demos
- is there a better way to expose tigerbeetle than binding to 0.0.0.0? The warning in `config.zig` is scary...
