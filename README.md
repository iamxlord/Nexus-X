### Nexus version X Prover Node:

``` Contribute Compute, Earn NEX Points ```



``` Become a vital part of the Nexus ecosystem by contributing your compute resources as a Prover Node! By doing so, you'll earn NEX Points, which track your valuable contributions. ```



**Why Run a Nexus Prover Node?**

 * Earn NEX Points: Your compute power directly translates into NEX Points, rewarding your participation.

 * Flexible Contribution: Use a variety of devices, including desktops, laptops, mobile phones, and Virtual Private Servers (VPS).

 * Centralized Management: Link and manage all your contributing devices from a single Nexus account.

 * Scalability: Run multiple prover nodes simultaneously, even on different browser tabs, to maximize your contributions.



### Get started with NEXUS

 * Create or login to your [Nexus Account](https://app.nexus.xyz/)

 * go to [nodes section](https://app.nexus.xyz/)



You can contribute to the Nexus ecosystem through two primary methods: via your web browser or via the Command Line Interface (CLI).



# Contribute via Web Browser (Easiest Method)

This is the simplest way to get started and is suitable for most users.

 * Log in to your dashboard: Go to https://app.nexus.xyz/ and log in to your Nexus account.

 * Start your node: On the dashboard, locate and click the "Start Node" button.

!note

 * You can run prover nodes on multiple browser tabs simultaneously.

 * This method works seamlessly on desktops, laptops.

 * More active computations mean more NEX Points for you.



# Contribute via CLI (Ubuntu PC/VPS)



System Recommendation:



 * RAM: 8GB or more

 * vCPU: 2 or more

 * Operating System: Ubuntu 24.04 (Older distro may encounter GLIBC compatibility issues.)



### Installation and Setup guide:

 * Install Dependencies:

  ```bash

sudo apt update && sudo apt upgrade -y

```

```bash

sudo apt install screen curl build-essential pkg-config libssl-dev git-all -y

sudo apt install protobuf-compiler -y

sudo apt update

```



 * Install Rust and its components:

```bash

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

```

```bash

source $HOME/.cargo/env

```

```bash

rustup target add riscv32i-unknown-none-elf

```


* Return back to the $HOME directory - let's cook! ❤️‍
```bash

cd

```

* clone the Repo:

```bash
git clone https://github.com/iamxlord/Nexus-X.git
```

```bash
cd Nexus-X
```

* Make it executable
  
```bash
chmod +x nexus.sh
```
* Run the script! 
```bash
sudo ./nexus.sh
```
follow the ON-screen prompts

### Creating a Node ID

***

You'll need a unique Node ID to link your CLI-based prover to your Nexus account:
Create Node ID via Web:

***

 * Go to https://app.nexus.xyz/nodes.

 * Click Add Node, then Add CLI Node.

 * Copy the generated node-id and go back to the previous step

