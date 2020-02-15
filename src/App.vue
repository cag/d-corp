<template>
  <div id="app">
    <img alt="D Corp logo" src="./assets/logo.png">
    <div>
      Block time: {{ latestBlock.timestamp }}<br>
      Current time: {{ Math.floor(now.getTime() / 1000) }}<br>
      <br>
      My ETH: {{ user.ethBalance }}<br>
      My WETH: {{ user.wethBalance }}<br>
      My STONK: {{ user.stonkBalance }}<br>
      <br>
      Next poke time: {{ dCorpData.nextMarketCapPollTime }}<br>
      Last STONK price: {{ dCorpData.lastStonkPrice }}<br>
      <br>
      <button v-on:click="poke">Poke</button><br>
      <br>
      Current STONK price: {{ exchangeData.currentStonkPrice }}<br>
      Exchange ETH reserve: {{ exchangeData.ethBalance }}<br>
      Exchange STONK reserve: {{ exchangeData.stonkBalance }}<br>
      <br>
      <strong>Buy STONK</strong><br>
      ETH investment amount: <input v-model="ethOfferAmount"><br>
      STONK: {{ stonkPurchaseAmount }}<br>
      <button v-on:click="buyStonk">Buy</button><br>
      <br>
      <strong>Sell STONK</strong><br>
      STONK sale amount: <input v-model="stonkSaleAmount"><br>
      ETH: {{ ethReturnAmount }}<br>
      <button v-on:click="sellStonk">Sell</button>
    </div>
    <HelloWorld />
  </div>
</template>

<script>
import TruffleContract from '@truffle/contract'
import HelloWorld from './components/HelloWorld.vue'

const web3 = new Web3(Web3.givenProvider || "ws://localhost:7545");

import DCorpArtifact from '../build/contracts/DCorp.json'
import IUniswapExchangeArtifact from '../build/contracts/IUniswapExchange.json'
import WETH9Artifact from '../build/contracts/WETH9.json'
import FPMMDeterministicFactoryArtifact from '../build/contracts/FPMMDeterministicFactory.json'
import ConditionalTokensArtifact from '../build/contracts/ConditionalTokens.json'

const [
  DCorp,
  IUniswapExchange,
  WETH9,
  FPMMDeterministicFactory,
  ConditionalTokens,
] = [
  DCorpArtifact,
  IUniswapExchangeArtifact,
  WETH9Artifact,
  FPMMDeterministicFactoryArtifact,
  ConditionalTokensArtifact,
].map((artifact) => {
  const C = TruffleContract(artifact);
  C.setProvider(web3.currentProvider);
  return C;
});

export default {
  name: 'App',
  components: {
    HelloWorld
  },
  data() {
    return {
      latestBlock: {},
      now: new Date(),
      user: {},
      dCorpData: {},
      exchangeData: {},
      ethOfferAmount: '',
      stonkSaleAmount: '',
    };
  },
  computed: {
    stonkPurchaseAmount() {
      return this.calcInputPrice(this.ethOfferAmount, this.exchangeData.ethBalance, this.exchangeData.stonkBalance);
    },
    ethReturnAmount() {
      return this.calcInputPrice(this.stonkSaleAmount, this.exchangeData.stonkBalance, this.exchangeData.ethBalance);
    },
  },
  methods: {
    calcInputPrice(inputAmount, inputReserve, outputReserve) {
      try {
        const inputAmountWithFee = web3.utils.toBN(web3.utils.toWei(inputAmount)).muln(997);
        const ethReserve = web3.utils.toBN(web3.utils.toWei(inputReserve));
        const stonkReserve = web3.utils.toBN(web3.utils.toWei(outputReserve));
        return web3.utils.fromWei(
          inputAmountWithFee.mul(stonkReserve).div(
            ethReserve.muln(1000).add(inputAmountWithFee)
          )
        );
      } catch(e) {
        console.error(e);
        return null;
      }

    },

    async poke() {
      await this.dCorp.poke();
    },

    async buyStonk() {
      await this.uniswapExchange.ethToTokenSwapInput(
        web3.utils.toWei(this.stonkPurchaseAmount),
        Math.floor(this.now.getTime() / 1000) + 600,
        { value: web3.utils.toWei(this.ethOfferAmount) },
      );
    },

    async sellStonk() {
      await this.dCorp.approve(
        this.uniswapExchange.address,
        web3.utils.toWei(this.stonkSaleAmount)
      );
      await this.uniswapExchange.tokenToEthSwapInput(
        web3.utils.toWei(this.stonkSaleAmount),
        web3.utils.toWei(this.ethReturnAmount),
        Math.floor(this.now.getTime() / 1000) + 600,
      );
    },

    updateChainState() {
      for(const [name, balanceQ] of [
        ['ethBalance', web3.eth.getBalance(this.userAccount)],
        ['wethBalance', this.weth.balanceOf(this.userAccount)],
        ['stonkBalance', this.dCorp.balanceOf(this.userAccount)],
      ])
        balanceQ.then(balance => this.user[name] = web3.utils.fromWei(balance), console.error);

      Promise.all([
        web3.eth.getBalance(this.uniswapExchange.address),
        this.dCorp.balanceOf(this.uniswapExchange.address),
      ]).then(([ethBalance, stonkBalance]) => {
        this.exchangeData.ethBalance = web3.utils.fromWei(ethBalance);
        this.exchangeData.stonkBalance = web3.utils.fromWei(stonkBalance);
        this.exchangeData.currentStonkPrice = web3.utils.fromWei(web3.utils.toBN(web3.utils.toWei(ethBalance)).div(web3.utils.toBN(stonkBalance)));
      }, console.error);

      this.dCorp.nextMarketCapPollTime().then(
        t => this.dCorpData.nextMarketCapPollTime = t,
        console.error,
      );
      this.dCorp.lastStonkPrice().then(
        p => this.dCorpData.lastStonkPrice = web3.utils.fromWei(p),
        console.error,
      );
    },
  },

  async mounted() {
    let account = web3.eth.defaultAccount;
    if (!account) {
      account = (await web3.eth.getAccounts())[0];
      web3.eth.defaultAccount = account;
    }

    if (account) {
      for (const C of [
        DCorp,
        IUniswapExchange,
        WETH9,
        FPMMDeterministicFactory,
        ConditionalTokens,
      ]) {
        C.defaults({ from: account });
      }
    }
    
    this.userAccount = account;

    this.dCorp = await DCorp.deployed();
    for (const [C, name] of [
      [WETH9, 'weth'],
      [IUniswapExchange, 'uniswapExchange'],
      [ConditionalTokens, 'conditionalTokens'],
      [FPMMDeterministicFactory, 'fpmmFactory'],
    ]) {
      this[name] = await C.at(await this.dCorp[name]());
    }

    this.latestBlock = await web3.eth.getBlock();
    this.updateChainState();

    this.nowInterval = setInterval(() => { this.now = new Date() }, 10)
    this.newBlockHeadersSubscription = web3.eth.subscribe('newBlockHeaders')
      .on("data", (blockHeader) => {
          this.latestBlock = blockHeader;
          this.updateChainState();
      })
      .on("error", console.error);
  },

  beforeDestroy() {
    clearInterval(this.nowInterval);
    this.nowInterval = null;
    this.newBlockHeadersSubscription.unsubscribe();
  },
}
</script>
