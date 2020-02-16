<template>
  <div id="app">
    <img alt="D Corp logo" src="./assets/logo.png">
    <div>
      Current time: {{ Math.floor(now.getTime() / 1000) }}<br>
      Block time: {{ latestBlock.timestamp }}<br>
      <br>
      My ETH: {{ user.ethBalance }}<br>
      My WETH: {{ user.wethBalance }}<br>
      My STONK: {{ user.stonkBalance }}<br>
      <br>
      Epoch period: {{ dCorpData.EPOCH_PERIOD }}<br>
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
      <button v-on:click="sellStonk">Sell</button><br>
      <br>
      <strong>Propose Transaction</strong><br>
      Available Time: <input v-model="txProposal.availableTime"><br>
      To: <input v-model="txProposal.to"><br>
      Value: <input v-model="txProposal.value"><br>
      Data: <input v-model="txProposal.data"><br>
      <button v-on:click="propose">Propose</button><br>
      <br>
      <h3>Proposal</h3>
      <select v-model="selectedProposal">
        <option value="">None</option>
        <option
          v-for="proposal in transactionProposals"
          v-bind:key="proposal.id"
          v-bind:value="proposal"
        >{{proposal.id}}</option>
      </select>
      <div v-if="selectedProposal">
        Available Time: {{ selectedProposal.availableTime }}<br>
        To: {{ toChecksumAddress(selectedProposal.to) }}<br>
        Value: {{ selectedProposal.value }}<br>
        Data: {{ selectedProposal.data }}<br>
      </div>
      <pre>{{ selectedProposal }}</pre>
    </div>
  </div>
</template>

<script>
import TruffleContract from '@truffle/contract'
import gql from 'graphql-tag'

import DCorpArtifact from '../build/contracts/DCorp.json'
import IUniswapExchangeArtifact from '../build/contracts/IUniswapExchange.json'
import WETH9Artifact from '../build/contracts/WETH9.json'
import FPMMDeterministicFactoryArtifact from '../build/contracts/FPMMDeterministicFactory.json'
import FixedProductMarketMakerArtifact from '../build/contracts/FixedProductMarketMaker.json'
import ConditionalTokensArtifact from '../build/contracts/ConditionalTokens.json'

export default {
  name: 'App',
  data() {
    return {
      latestBlock: {},
      now: new Date(),
      user: {},
      dCorpData: {},
      exchangeData: {},
      ethOfferAmount: '',
      stonkSaleAmount: '',
      txProposal: {},
      transactionProposals: [],
      selectedProposal: '',
      selectedProposalData: {},
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
  watch: {
    async selectedProposal(newProposal) {
      this.selectedProposalData = {};
      if (!newProposal) return;

      this.selectedProposalData.fpmm =
        await this.FixedProductMarketMaker.at(newProposal.fpmm);

      this.updateSelectedFpmmState();
    }
  },
  methods: {
    calcInputPrice(inputAmount, inputReserve, outputReserve) {
      try {
        const inputAmountWithFee = Web3.utils.toBN(Web3.utils.toWei(inputAmount)).muln(997);
        const ethReserve = Web3.utils.toBN(Web3.utils.toWei(inputReserve));
        const stonkReserve = Web3.utils.toBN(Web3.utils.toWei(outputReserve));
        return Web3.utils.fromWei(
          inputAmountWithFee.mul(stonkReserve).div(
            ethReserve.muln(1000).add(inputAmountWithFee)
          )
        );
      } catch(e) {
        return null;
      }
    },

    toChecksumAddress: Web3.utils.toChecksumAddress,

    async poke() {
      await this.dCorp.poke();
    },

    async buyStonk() {
      await this.uniswapExchange.ethToTokenSwapInput(
        Web3.utils.toWei(this.stonkPurchaseAmount),
        Math.floor(this.now.getTime() / 1000) + 600,
        { value: Web3.utils.toWei(this.ethOfferAmount) },
      );
    },

    async sellStonk() {
      await this.dCorp.approve(
        this.uniswapExchange.address,
        Web3.utils.toWei(this.stonkSaleAmount)
      );
      await this.uniswapExchange.tokenToEthSwapInput(
        Web3.utils.toWei(this.stonkSaleAmount),
        Web3.utils.toWei(this.ethReturnAmount),
        Math.floor(this.now.getTime() / 1000) + 600,
      );
    },

    async propose() {
      await this.dCorp.propose(this.txProposal);
    },

    updateChainState() {
      for(const [name, balanceQ] of [
        ['ethBalance', this.web3.eth.getBalance(this.userAccount)],
        ['wethBalance', this.weth.balanceOf(this.userAccount)],
        ['stonkBalance', this.dCorp.balanceOf(this.userAccount)],
      ])
        balanceQ.then(balance => this.user[name] = Web3.utils.fromWei(balance), console.error);

      Promise.all([
        this.web3.eth.getBalance(this.uniswapExchange.address),
        this.dCorp.balanceOf(this.uniswapExchange.address),
      ]).then(([ethBalance, stonkBalance]) => {
        this.exchangeData.ethBalance = Web3.utils.fromWei(ethBalance);
        this.exchangeData.stonkBalance = Web3.utils.fromWei(stonkBalance);
        this.exchangeData.currentStonkPrice = Web3.utils.fromWei(Web3.utils.toBN(Web3.utils.toWei(ethBalance)).div(Web3.utils.toBN(stonkBalance)));
      }, console.error);

      for(const prop of [
        'EPOCH_PERIOD',
        'startTime',
        'nextMarketCapPollTime',
      ]) {
        this.dCorp[prop]().then(
          t => this.dCorpData[prop] = t,
          console.error,
        );
      }

      this.dCorp.lastStonkPrice().then(
        p => this.dCorpData.lastStonkPrice = Web3.utils.fromWei(p),
        console.error,
      );

      this.updateSelectedFpmmState();
    },

    updateSelectedFpmmState() {
      const { fpmm } = this.selectedProposalData;
      if (!fpmm) return;

      console.log('do stuff here')
    }
  },

  async mounted() {
    const web3 = new Web3(Web3.givenProvider || "ws://localhost:8545");
    this.web3 = web3;

    const [
      DCorp,
      IUniswapExchange,
      WETH9,
      FPMMDeterministicFactory,
      FixedProductMarketMaker,
      ConditionalTokens,
    ] = [
      DCorpArtifact,
      IUniswapExchangeArtifact,
      WETH9Artifact,
      FPMMDeterministicFactoryArtifact,
      FixedProductMarketMakerArtifact,
      ConditionalTokensArtifact,
    ].map((artifact) => {
      const C = TruffleContract(artifact);
      C.setProvider(web3.currentProvider);
      return C;
    });

    this.FixedProductMarketMaker = FixedProductMarketMaker;

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
        FixedProductMarketMaker,
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

  apollo: {
    transactionProposals: gql`{
      transactionProposals {
        id
        availableTime
        to
        value
        data
        fpmm
        isPendingResolution
        executed
      }
    }`,
  },
}
</script>
