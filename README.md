# WireGuard installer

**This project is a bash script that aims to setup a [WireGuard](https://www.wireguard.com/) VPN on a Linux server, as easily as possible!**

WireGuard is a point-to-point VPN that can be used in different ways. Here, we mean a VPN as in: the client will forward all its traffic through an encrypted tunnel to the server.
The server will apply NAT to the client's traffic so it will appear as if the client is browsing the web with the server's IP.

The script supports both IPv4 and IPv6. Please check the [issues](https://github.com/W01v3n/wireguard-install/issues) for ongoing development, bugs and planned features! You might also want to check the [discussions](https://github.com/W01v3n/wireguard-install/discussions) for help.

## Requirements

Supported distributions:

- AlmaLinux >= 8
- Arch Linux
- CentOS Stream >= 8
- Debian >= 10
- Fedora >= 32
- Oracle Linux
- Rocky Linux >= 8
- Ubuntu >= 18.04

## Usage

Download and execute the script and it will take care of the rest.
There's another version of this script that asks questions and configures WireGuard according to the answers.
If you prefer that, you can check the script in the [original](https://github.com/angristan/wireguard-install) repository.

```bash
curl -O https://raw.githubusercontent.com/W01v3n/wireguard-install/master/wireguard-install.sh
chmod +x wireguard-install.sh
./wireguard-install.sh
```

It will install WireGuard (kernel module and tools) on the server, configure it, create a systemd service and a client configuration file, all automatically, no prompts.

Run the script again to add or remove clients!

## Providers

I recommend these cheap cloud providers for your VPN server:

- [Vultr](https://www.vultr.com/?ref=8948982-8H): Worldwide locations, IPv6 support, starting at \$5/month
- [Hetzner](https://hetzner.cloud/?ref=ywtlvZsjgeDq): Germany, Finland and USA. IPv6, 20 TB of traffic, starting at 4.5€/month
- [Digital Ocean](https://m.do.co/c/ed0ba143fe53): Worldwide locations, IPv6 support, starting at \$4/month

## Contributing

## Discuss changes

Please open an issue before submitting a PR if you want to discuss a change, especially if it's a big one.

### Code formatting

We use [shellcheck](https://github.com/koalaman/shellcheck) and [shfmt](https://github.com/mvdan/sh) to enforce bash styling guidelines and good practices. They are executed for each commit / PR with GitHub Actions, so you can check the configuration [here](https://github.com/W01v3n/wireguard-install/blob/master/.github/workflows/lint.yml).

## Say thanks

You can [say thanks](https://saythanks.io/to/W01v3n) if you want!

## Credits & Licence

This project is under the [MIT Licence](https://raw.githubusercontent.com/W01v3n/wireguard-install/master/LICENSE)
And was forked from the [original](https://github.com/angristan/wireguard-install) repository.

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=W01v3n/wireguard-install&type=Date)](https://star-history.com/#W01v3n/wireguard-install&Date)
