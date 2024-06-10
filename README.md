# Degen Option Core

![do-banner](https://github.com/Semantic-Layer/degenOption-contracts/assets/56213581/1145d9e2-1c9c-4257-8336-97887e95de08)

Degen Option is a new type options for incentivizing trading volumes. Degen Options is issued to token buyers via Uniswap V4 Hook, and 1 DO gives the holder the right to purchase 1 underlying token at the strike price.

## Degen Option Dashboard Preview

https://degen-option.web.app/

## Introduction

Below is a TLDR; Visit [here](https://www.semanticlayer.io/blog/6) for a detailed writeup.

### What is Degen Option?

Degen Option is a Uniswap V4 hook that rewards users based on their trading volume, by giving them degen options (DO), which is a non-fungible token that is tradable and gives the holder the right to purchase additional tokens at a fixed strike price.

### Why is it called Degen Option?

Degen Option exhibits some properties similar to American options, where it can be exercised anytime before the expiry. However, DO expiry is not time-based but triggered by the price of the underlying token.

### How does Degen Option work?

DO farms can be deployed as Uniswap V4 Hooks for rewarding trading volumes. Traders will receive DO based on their trading volume, and they can exercise anytime before the token price drops below the DO expiry price.

### What can DO be used for?

DO farms incentivizes trading volume for Uniswap V4 pools with an option mechanism, which aligns the interest of short-term/long-term holders, traders, and liquidity providers.

## Usage

This repo contains core smart contracts of Degen Option. Some commands to use these contracts with Foundry:

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

## Contributions

Contributions make our community vibrant and dynamic. Whether it's fixing bugs, adding new features, or improving documentation, all contributions are welcome.

### Reporting Issues
Find a bug or have a feature request? Please create an [issue](https://github.com/Semantic-Layer/degenOption-contracts/issues).
