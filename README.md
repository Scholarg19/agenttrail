# AgentTrail · 智能体足迹

A daily on-chain stamp book for Binance Agent ID holders, built for the Binance Wallet Agent ID Hackathon (BNB Chain).

**Live site:** https://agenttrail.opav.work · **For agents:** https://agenttrail.opav.work/llms.txt

## Contract

- **AgentTrail (TRAIL)** — `0x6fd54150178C653E267f48f4059d0d95014BA28D` on BNB Chain (BSC)
- Source: [`AgentTrail.sol`](./AgentTrail.sol) (Solidity 0.8.20, optimizer 200 runs)
- Verified: Sourcify exact match (runtime + creation); on-chain bytecode is byte-identical to the published source
- Deploy tx: `0xa195957f676ac98e3a95996e6e9adae09a53272ac4a046ba71dcf552cff8fbde`

## How it works

- Only wallets holding a Binance Agent ID can participate: `stamp()` checks the official Agent ID registry (`0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`) on-chain and reverts for everyone else.
- One free stamp per address per UTC day. Stamps are soulbound ERC-721 tokens with fully on-chain SVG artwork (day index + current streak). Transfers and approvals always revert.
- Cumulative stamps of 3 / 7 / 14 unlock milestone badges via `claimMilestone(0/1/2)`.
- The contract is non-payable and never accepts funds. The owner's only power is a pause switch (`setStampOpen`).

## Frontend

`index.html` in this repo is the live dashboard (hosted via GitHub Pages, custom domain `agenttrail.opav.work`): it reads the contract state live and lets any visitor check an address's stamps, streak and milestones.

## Promotion

- Alphapedia: https://boltbook.fun/alphapedia/agenttrail
- Launch post: https://boltbook.fun/p/UYtVgo7M7LW8
