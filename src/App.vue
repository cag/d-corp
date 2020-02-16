<style scoped>
#app {
  margin: 1em;
}

.logo {
  display: block;
  margin: 1em auto;
  width: 25%;
  max-width: 100px;
}

.line {
  display: flex;
  flex-wrap: wrap;
}

.block {
  margin: 1em;
}

.proposal {
  background-color: seashell;
}

</style>

<template>
  <div id="app">
    <div><img class="logo" alt="D Corp logo" src="./assets/logo.png"></div>
    <div class="line">
      <div class='block'>
        Current time: {{ now.toLocaleString() }}<br>
        Block time: {{ formatTimestamp(latestBlock.timestamp) }}
      </div>
      <div class='block'>
        My ETH: {{ user.ethBalance }}<br>
        My WETH: {{ user.wethBalance }}<br>
        My STONK: {{ user.stonkBalance }}<br>
      </div>
      <div class='block'>
        Epoch period: {{ dCorpData.EPOCH_PERIOD }}<br>
        Next poke time: {{ formatTimestamp(dCorpData.nextMarketCapPollTime) }}<br>
        Last STONK price: {{ dCorpData.lastStonkPrice }}<br>
        <br>
        <button v-on:click="poke">Poke</button><br>
      </div>
    </div>
    <div class="line">
      <div class='block'>
        Current STONK price: {{ exchangeData.currentStonkPrice }}<br>
        Exchange ETH reserve: {{ exchangeData.ethBalance }}<br>
        Exchange STONK reserve: {{ exchangeData.stonkBalance }}<br>
      </div>
      <div class='block'>
        <strong>Buy STONK</strong><br>
        ETH investment amount: <input v-model="ethOfferAmount"><br>
        STONK: {{ stonkPurchaseAmount }}<br>
        <button v-on:click="buyStonk">Buy</button><br>
      </div>
      <div class='block'>
        <strong>Sell STONK</strong><br>
        STONK sale amount: <input v-model="stonkSaleAmount"><br>
        ETH: {{ ethReturnAmount }}<br>
        <button v-on:click="sellStonk">Sell</button><br>
      </div>
    </div>
    <div class="line">
      <div class='block'>
        <strong>Propose Transaction</strong><br>
        Available {{ formatTimestamp(txProposal.availableTime) }}<br>
        <button v-on:click="resetTime">Reset</button>
        <button v-on:click="advanceTime">></button><br>
        To: <input v-model="txProposal.to"><br>
        Value: <input v-model="txProposal.value"><br>
        Data: <input v-model="txProposal.data"><br>
        <button v-on:click="propose">Propose</button><br>
      </div>
      <div>
        <h3>Proposal</h3>
        <select v-model="selectedProposal">
          <option value="">None</option>
          <option
            v-for="proposal in transactionProposals"
            v-bind:key="proposal.id"
            v-bind:value="proposal"
          >{{proposal.id}}</option>
        </select>
      </div>
    </div>
    <div class="proposal" v-if="selectedProposal">
      <div class="line">
        <div class="block">
          Time when executable: {{ formatTimestamp(selectedProposal.availableTime) }}<br>
          To: {{ toChecksumAddress(selectedProposal.to) }}<br>
          Value: {{ selectedProposal.value }}<br>
          Data: {{ selectedProposal.data }}<br>
          Still pending? {{ selectedProposal.isPendingResolution ? 'Yes.' : 'No.' }}<br>
          <span v-if="!selectedProposal.isPendingResolution">
            Executed? {{ selectedProposal.executed ? 'Yes.' : 'No.' }}<br>
          </span>
          <button v-on:click="doOrDoNot">Do or do not</button><br>
        </div>
        <div class="block">
          My pool tokens: {{ selectedProposalData.userPoolBalance }}<br>
          My outcome tokens:<br>
          <span
            v-for="(balance, index) in selectedProposalData.userOutcomeTokens"
            v-bind:key="index"
          >{{ outcomeNames[index] }}: {{ balance }}<br></span>
          <button v-on:click="redeemOutcomeTokens">Redeem</button><br>
        </div>
        <div class="block">
          Pool token supply: {{ selectedProposalData.poolTokenSupply }}<br>
          Pool outcome tokens:<br>
          <span
            v-for="(balance, index) in selectedProposalData.outcomeTokenBalances"
            v-bind:key="index"
          >{{ outcomeNames[index] }}: {{ balance }}<br></span>
          Pool fee factor: {{ selectedProposalData.feeFactor }}<br>
        </div>
      </div>
      <div class="line">
        <div class="block">
          <strong>Enter Pool</strong><br>
          Added funding (ETH): <input v-model="additionalFunding"><br>
          Distribution hint: <input v-model="distributionHint"><br>
          <button v-on:click="addFunding">Enter</button><br>
        </div>
        <div class="block">
          <strong>Exit Pool</strong><br>
          Pool tokens to burn: <input v-model="poolTokensToBurn"><br>
          <button v-on:click="removeFunding">Exit</button><br>
        </div>
      </div>
      <div class="line">
        <div class="block">
          <strong>Buy Outcome Tokens</strong><br>
          ETH to bet: <input v-model="ethToBet"><br>
          <select v-model="buyOutcomeIndex">
            <option :value="0">Does TX and STONK goes high</option>
            <option :value="1">Does TX and STONK goes low</option>
            <option :value="2">Skips TX and STONK goes high</option>
            <option :value="3">Skips TX and STONK goes low</option>
          </select><br>
          Outcome token purchase amount: {{ outcomeTokenPurchaseAmount }}<br>
          <button v-on:click="buyOutcomeTokens">Buy</button><br>
        </div>
        <div class="block">
          <strong>Sell Outcome Tokens</strong><br>
          ETH to receive: <input v-model="ethToReceive"><br>
          <select v-model="sellOutcomeIndex">
            <option :value="0">Does TX and STONK goes high</option>
            <option :value="1">Does TX and STONK goes low</option>
            <option :value="2">Skips TX and STONK goes high</option>
            <option :value="3">Skips TX and STONK goes low</option>
          </select><br>
          Outcome token sale amount: {{ outcomeTokenSaleAmount }}<br>
          <button v-on:click="sellOutcomeTokens">Sell</button><br>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import TruffleContract from '@truffle/contract'
import gql from 'graphql-tag'
import makeIdHelpers from '@gnosis.pm/conditional-tokens-contracts/utils/id-helpers'

const { getConditionId, getCollectionId, combineCollectionIds, getPositionId } = makeIdHelpers(Web3.utils);

const {
  toBN,
  fromWei,
  toWei,
  toChecksumAddress,
  padLeft,
  toHex,
} = Web3.utils;

const ceildiv = (x, y) => x.gtn(0) ? x.subn(1).div(y).addn(1) : x.div(y);

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
      additionalFunding: '',
      distributionHint: '',
      poolTokensToBurn: '',
      ethToBet: '',
      buyOutcomeIndex: 0,
      ethToReceive: '',
      sellOutcomeIndex: 0,
      outcomeNames: [
        'Does + High',
        'Does + Low',
        'Skips + High',
        'Skips + Low',
      ],
    };
  },
  computed: {
    stonkPurchaseAmount() {
      return this.calcInputPrice(this.ethOfferAmount, this.exchangeData.ethBalance, this.exchangeData.stonkBalance);
    },
    ethReturnAmount() {
      return this.calcInputPrice(this.stonkSaleAmount, this.exchangeData.stonkBalance, this.exchangeData.ethBalance);
    },
    outcomeTokenPurchaseAmount() {
      try {
        const ONE = toBN(toWei('1'));
        const poolBalances = this.selectedProposalData.outcomeTokenBalances.map(
          balance => toBN(toWei(balance))
        );
        const investmentAmount = toBN(toWei(this.ethToBet));
        const investmentAmountMinusFees = investmentAmount.sub(
          investmentAmount.mul(
            toBN(toWei(this.selectedProposalData.feeFactor))
          ).div(ONE)
        );
        const buyTokenPoolBalance = poolBalances[this.buyOutcomeIndex];
        let endingOutcomeBalance = buyTokenPoolBalance.mul(ONE);
        poolBalances.forEach((poolBalance, i) => {
          if (i !== this.buyOutcomeIndex) {
            endingOutcomeBalance = ceildiv(
              endingOutcomeBalance.mul(poolBalance),
              poolBalance.add(investmentAmountMinusFees)
            );
          }
        })
  
        return fromWei(buyTokenPoolBalance.add(investmentAmount).sub(ceildiv(endingOutcomeBalance, ONE)));
      } catch(e) {
        return null;
      }
    },
    outcomeTokenSaleAmount() {
      try {
        const ONE = toBN(toWei('1'));
        const poolBalances = this.selectedProposalData.outcomeTokenBalances.map(
          balance => toBN(toWei(balance))
        );
        const returnAmount = toBN(toWei(this.ethToReceive));
        const returnAmountPlusFees = returnAmount.add(
          returnAmount.mul(
            toBN(toWei(this.selectedProposalData.feeFactor))
          ).div(ONE)
        );
        const sellTokenPoolBalance = poolBalances[this.sellOutcomeIndex];
        let endingOutcomeBalance = sellTokenPoolBalance.mul(ONE);
        poolBalances.forEach((poolBalance, i) => {
          if (i !== this.sellOutcomeIndex) {
            endingOutcomeBalance = ceildiv(
              endingOutcomeBalance.mul(poolBalance),
              poolBalance.sub(returnAmountPlusFees)
            );
          }
        })
  
        return fromWei(returnAmount.add(ceildiv(endingOutcomeBalance, ONE)).sub(sellTokenPoolBalance));
      } catch(e) {
        return null;
      }
    }
  },
  watch: {
    async selectedProposal(newProposal) {
      this.selectedProposalData = {};
      if (!newProposal) return;

      this.$set(
        this.selectedProposalData,
        'fpmm',
        await this.FixedProductMarketMaker.at(newProposal.fpmm),
      );

      this.selectedProposalData.fpmm.fee().then(
        feeFactor => this.$set(this.selectedProposalData, 'feeFactor', fromWei(feeFactor)),
        console.error,
      );

      this.updateSelectedFpmmState();
    },

    transactionProposals(newProposals) {
      if (!this.selectedProposal) return;
      const matchingSelected = newProposals.find(({ id }) => id === this.selectedProposal.id);
      if (matchingSelected != null)
        this.selectedProposal = matchingSelected;
    }
  },
  methods: {
    formatTimestamp(ts) {
      return new Date(ts * 1000).toLocaleString();
    },

    calcInputPrice(inputAmount, inputReserve, outputReserve) {
      try {
        const inputAmountWithFee = toBN(toWei(inputAmount)).muln(997);
        const ethReserve = toBN(toWei(inputReserve));
        const stonkReserve = toBN(toWei(outputReserve));
        return fromWei(
          inputAmountWithFee.mul(stonkReserve).div(
            ethReserve.muln(1000).add(inputAmountWithFee)
          )
        );
      } catch(e) {
        return null;
      }
    },

    toChecksumAddress,

    resetTime() {
      const startTime = this.dCorpData.startTime.toNumber()
      const EPOCH_PERIOD = this.dCorpData.EPOCH_PERIOD.toNumber()

      this.$set(this.txProposal, 'availableTime',
        startTime + EPOCH_PERIOD * (1 + Math.ceil(
          (this.now.getTime() / 1000 - startTime) /
          EPOCH_PERIOD
        ))
      );
    },

    advanceTime() {
      const EPOCH_PERIOD = this.dCorpData.EPOCH_PERIOD.toNumber()

      this.$set(this.txProposal, 'availableTime', this.txProposal.availableTime + EPOCH_PERIOD);

    },

    async poke() {
      await this.dCorp.poke();
    },

    async buyStonk() {
      await this.uniswapExchange.ethToTokenSwapInput(
        toWei(this.stonkPurchaseAmount),
        Math.floor(this.now.getTime() / 1000) + 600,
        { value: toWei(this.ethOfferAmount) },
      );
    },

    async sellStonk() {
      await this.dCorp.approve(
        this.uniswapExchange.address,
        toWei(this.stonkSaleAmount)
      );
      await this.uniswapExchange.tokenToEthSwapInput(
        toWei(this.stonkSaleAmount),
        toWei(this.ethReturnAmount),
        Math.floor(this.now.getTime() / 1000) + 600,
      );
    },

    async propose() {
      await this.dCorp.propose(this.txProposal);
    },

    async addFunding() {
      const { fpmm } = this.selectedProposalData;
      const addedFunds = toWei(this.additionalFunding);
      const hint = this.distributionHint ? JSON.parse(this.distributionHint) : [];
      await this.weth.deposit({ value: addedFunds });
      await this.weth.approve(fpmm.address, addedFunds);
      await fpmm.addFunding(addedFunds, hint);
    },

    async removeFunding() {
      const { fpmm } = this.selectedProposalData;
      const sharesToBurn = toWei(this.poolTokensToBurn);
      await fpmm.removeFunding(sharesToBurn);
    },

    async buyOutcomeTokens() {
      const { fpmm } = this.selectedProposalData;
      const investmentAmount = toWei(this.ethToBet);
      const minOutcomeTokensToBuy = toWei(this.outcomeTokenPurchaseAmount);
      await this.weth.deposit({ value: investmentAmount });
      await this.weth.approve(fpmm.address, investmentAmount);
      await fpmm.buy(investmentAmount, this.buyOutcomeIndex, minOutcomeTokensToBuy);
    },

    async sellOutcomeTokens() {
      const { fpmm } = this.selectedProposalData;
      const returnAmount = toWei(this.ethToReceive);
      const maxOutcomeTokensToSell = toWei(this.outcomeTokenSaleAmount);
      await this.conditionalTokens.setApprovalForAll(fpmm.address, returnAmount);
      await fpmm.sell(returnAmount, this.sellOutcomeIndex, maxOutcomeTokensToSell);
    },

    async doOrDoNot() {
      await this.dCorp.doOrDoNot({
        availableTime: this.selectedProposal.availableTime,
        to: this.selectedProposal.to,
        value: this.selectedProposal.value,
        data: this.selectedProposal.data,
      }, { gas: 6000000 });
    },

    async redeemOutcomeTokens() {
      const txConditionId = getConditionId(
        this.dCorp.address,
        this.selectedProposal.id,
        2,
      );

      const pollConditionId = getConditionId(
        this.dCorp.address,
        padLeft(
          toHex(
            this.dCorpData.EPOCH_PERIOD.add(
              toBN(this.selectedProposal.availableTime)
            )
          ),
          64
        ),
        2,
      );

      await this.conditionalTokens.redeemPositions(
        this.weth.address,
        getCollectionId(pollConditionId, 0b01),
        txConditionId,
        [0b01, 0b10]
      );

      await this.conditionalTokens.redeemPositions(
        this.weth.address,
        getCollectionId(pollConditionId, 0b10),
        txConditionId,
        [0b01, 0b10]
      );

      await this.conditionalTokens.redeemPositions(
        this.weth.address,
        '0x',
        pollConditionId,
        [0b01, 0b10]
      );
    },

    updateChainState(shouldResetTime) {
      for(const [name, balanceQ] of [
        ['ethBalance', this.web3.eth.getBalance(this.userAccount)],
        ['wethBalance', this.weth.balanceOf(this.userAccount)],
        ['stonkBalance', this.dCorp.balanceOf(this.userAccount)],
      ])
        balanceQ.then(balance => this.$set(this.user, name, fromWei(balance)), console.error);

      Promise.all([
        this.web3.eth.getBalance(this.uniswapExchange.address),
        this.dCorp.balanceOf(this.uniswapExchange.address),
      ]).then(([ethBalance, stonkBalance]) => {
        this.$set(this.exchangeData, 'ethBalance', fromWei(ethBalance));
        this.$set(this.exchangeData, 'stonkBalance', fromWei(stonkBalance));
        this.$set(this.exchangeData, 'currentStonkPrice', fromWei(toBN(toWei(ethBalance)).div(toBN(stonkBalance))));
      }, console.error);

      for(const prop of [
        'EPOCH_PERIOD',
        'startTime',
        'nextMarketCapPollTime',
      ]) {
        this.dCorp[prop]().then(
          t => {
            this.$set(this.dCorpData, prop, t);
            if (shouldResetTime) {
              this.resetTime();
            }
          },
          console.error,
        );
      }


      this.dCorp.lastStonkPrice().then(
        p => this.$set(this.dCorpData, 'lastStonkPrice', fromWei(p)),
        console.error,
      );

      this.updateSelectedFpmmState();
    },

    updateSelectedFpmmState() {
      if (!this.selectedProposal)
        return;

      const txConditionId = getConditionId(
        this.dCorp.address,
        this.selectedProposal.id,
        2,
      );
      const pollConditionId = getConditionId(
        this.dCorp.address,
        padLeft(
          toHex(
            this.dCorpData.EPOCH_PERIOD.add(
              toBN(this.selectedProposal.availableTime)
            )
          ),
          64
        ),
        2,
      );

      const positionIds = Array.from({ length: 4 }, (v, i) =>
        getPositionId(
          this.weth.address,
          combineCollectionIds([
            getCollectionId(txConditionId, 1 << (i >> 1)),
            getCollectionId(pollConditionId, 1 << (i & 1)),
          ]),
        )
      )

      this.conditionalTokens.balanceOfBatch(
        new Array(4).fill(this.userAccount),
        positionIds
      ).then(
        balances => this.$set(
          this.selectedProposalData,
          'userOutcomeTokens',
          balances.map(v => fromWei(v))
        ),
        console.error
      );

      const { fpmm } = this.selectedProposalData;
      if (!fpmm) return;

      fpmm.balanceOf(this.userAccount).then(
        balance => this.$set(this.selectedProposalData, 'userPoolBalance', fromWei(balance)),
        console.error
      );

      fpmm.totalSupply().then(
        balance => this.$set(this.selectedProposalData, 'poolTokenSupply', fromWei(balance)),
        console.error
      )

      this.conditionalTokens.balanceOfBatch(
        new Array(4).fill(fpmm.address),
        positionIds
      ).then(
        balances => this.$set(
          this.selectedProposalData,
          'outcomeTokenBalances',
          balances.map(v => fromWei(v)),
        ),
        console.error
      );
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
    this.updateChainState(true);

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
    transactionProposals: {
      query: gql`{
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
      pollInterval: 500,
    },
  },
}
</script>
