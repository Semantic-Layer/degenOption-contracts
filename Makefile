include .env

.PHONY: deploy
deploy:
	forge script script/Deploy.s.sol:Deploy --broadcast --rpc-url ${SEPOLIA_RPC_URL} -vvvv

.PHONY: mineAddress
mineAddress:
	forge script script/Deploy.s.sol:MineAddress --broadcast --rpc-url ${SEPOLIA_RPC_URL} -vvv
