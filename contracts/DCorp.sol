pragma solidity >=0.5.0 <0.7.0;
pragma experimental ABIEncoderV2;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { IUniswapFactory } from "project-name/contracts/interfaces/IUniswapFactory.sol";
import { IUniswapExchange } from "project-name/contracts/interfaces/IUniswapExchange.sol";
import { ConditionalTokens } from "@gnosis.pm/conditional-tokens-contracts/contracts/ConditionalTokens.sol";
import { CTHelpers } from "@gnosis.pm/conditional-tokens-contracts/contracts/CTHelpers.sol";
import { FixedProductMarketMaker } from "@gnosis.pm/conditional-tokens-market-makers/contracts/FixedProductMarketMaker.sol";
import { FPMMDeterministicFactory, IERC20 } from "@gnosis.pm/conditional-tokens-market-makers/contracts/FPMMDeterministicFactory.sol";
import { WETH9 } from "canonical-weth/contracts/WETH9.sol";

contract DCorp is ERC20 {
  using SafeMath for uint;

  string public constant name = "D Corp Stonk";
  string public constant symbol = "STONK";
  uint public constant decimals = 18;

  WETH9 public weth;

  IUniswapFactory public uniswapFactory;
  IUniswapExchange public uniswapExchange;

  ConditionalTokens public conditionalTokens;

  FPMMDeterministicFactory public fpmmFactory;

  uint constant START_AMOUNT = 100 ether;
  uint public constant EPOCH_PERIOD = 10;
  uint constant FPMM_FEE = 0.01 ether;

  uint public startTime;
  uint public nextMarketCapPollTime;
  uint public lastStonkPrice;

  constructor(WETH9 _weth, IUniswapFactory _uniswapFactory, ConditionalTokens _conditionalTokens, FPMMDeterministicFactory _fpmmFactory) public {
    weth = _weth;
    uniswapFactory = _uniswapFactory;
    conditionalTokens = _conditionalTokens;
    fpmmFactory = _fpmmFactory;
  }

  function setup() external payable {
    require(address(uniswapExchange) == address(0), "already setup");
    address payable exchange = uniswapFactory.createExchange(address(this));

    _mint(address(this), START_AMOUNT);
    _approve(address(this), exchange, START_AMOUNT);
    IUniswapExchange(exchange).addLiquidity.value(msg.value)(0, START_AMOUNT, uint(-1));
    lastStonkPrice = uint(1 ether).mul(exchange.balance) / balanceOf(exchange);

    uniswapExchange = IUniswapExchange(exchange);
    startTime = block.timestamp;
    nextMarketCapPollTime = startTime.add(EPOCH_PERIOD);
  }

  struct TransactionProposal {
    uint availableTime;

    address to;
    uint value;
    bytes data;
  }

  event TransactionProposed(
    bytes32 indexed proposalHash,
    uint indexed availableTime,
    address indexed to,
    uint value,
    bytes data,
    FixedProductMarketMaker fpmm
  );

  mapping (bytes32 => FixedProductMarketMaker) proposedTransactions;

  function propose(TransactionProposal calldata proposal) external payable {
    bytes32 proposalHash = keccak256(abi.encode(proposal));

    require(
      proposedTransactions[proposalHash] == FixedProductMarketMaker(0),
      "transaction already proposed"
    );

    require(
      proposal.availableTime.sub(startTime, "proposal time must be after") % EPOCH_PERIOD == 0,
      "proposal available time must be aligned"
    );

    require(
      proposal.availableTime > block.timestamp + EPOCH_PERIOD,
      "proposal must have an epoch for deciding"
    );

    conditionalTokens.prepareCondition(address(this), proposalHash, 2);
    bytes32 txConditionId = keccak256(abi.encodePacked(address(this), proposalHash, uint(2)));

    bytes32 pollConditionId = CTHelpers.getConditionId(
      address(this),
      bytes32(proposal.availableTime.add(EPOCH_PERIOD)),
      2
    );
    if (conditionalTokens.getOutcomeSlotCount(pollConditionId) == 0) {
      conditionalTokens.prepareCondition(
        address(this),
        bytes32(proposal.availableTime.add(EPOCH_PERIOD)),
        2
      );
    }

    bytes32[] memory conditionIds = new bytes32[](2);
    conditionIds[0] = pollConditionId;
    conditionIds[1] = txConditionId;

    FixedProductMarketMaker fpmm = fpmmFactory.create2FixedProductMarketMaker(
      uint(bytes32("LAND OF ECODELIA")),
      conditionalTokens,
      IERC20(address(weth)),
      conditionIds,
      FPMM_FEE,
      0,
      new uint[](0)
    );

    proposedTransactions[proposalHash] = fpmm;

    emit TransactionProposed(
      proposalHash,
      proposal.availableTime,
      proposal.to,
      proposal.value,
      proposal.data,
      fpmm
    );
  }

  event TransactionProposalResolved(
    bytes32 indexed proposalHash,
    uint indexed availableTime,
    address indexed to,
    bool executed
  );

  function doOrDoNot(TransactionProposal calldata proposal) external payable {
    bytes32 proposalHash = keccak256(abi.encode(proposal));

    FixedProductMarketMaker fpmm = proposedTransactions[proposalHash];

    require(fpmm != FixedProductMarketMaker(0), "transaction missing");

    uint[] memory balances;
    {
      uint[] memory positionIds = new uint[](4);
      {
        bytes32 txConditionId = keccak256(abi.encodePacked(address(this), proposalHash, uint(2)));

        bytes32 pollConditionId = CTHelpers.getConditionId(
          address(this),
          bytes32(proposal.availableTime.add(EPOCH_PERIOD)),
          2
        );

        // Yes Lo
        positionIds[0] = CTHelpers.getPositionId(IERC20(address(weth)), CTHelpers.getCollectionId(
          CTHelpers.getCollectionId(bytes32(0), txConditionId, 1),
          pollConditionId, 1
        ));
        // Yes Hi
        positionIds[1] = CTHelpers.getPositionId(IERC20(address(weth)), CTHelpers.getCollectionId(
          CTHelpers.getCollectionId(bytes32(0), txConditionId, 1),
          pollConditionId, 2
        ));
        // No Lo
        positionIds[2] = CTHelpers.getPositionId(IERC20(address(weth)), CTHelpers.getCollectionId(
          CTHelpers.getCollectionId(bytes32(0), txConditionId, 2),
          pollConditionId, 1
        ));
        // No Hi
        positionIds[3] = CTHelpers.getPositionId(IERC20(address(weth)), CTHelpers.getCollectionId(
          CTHelpers.getCollectionId(bytes32(0), txConditionId, 2),
          pollConditionId, 2
        ));
      }

      address[] memory exchangeArr = new address[](4);
      exchangeArr[0] = address(fpmm);
      exchangeArr[1] = address(fpmm);
      exchangeArr[2] = address(fpmm);
      exchangeArr[3] = address(fpmm);
      balances = conditionalTokens.balanceOfBatch(exchangeArr, positionIds);
    }

    uint[] memory payouts = new uint[](2);
    bool execute = balances[1].mul(balances[2]) > balances[0].mul(balances[3]);
    if (execute) {
      // do
      payouts[0] = 1; payouts[1] = 0;
      conditionalTokens.reportPayouts(proposalHash, payouts);
      (bool success, bytes memory retdata) = proposal.to.call.value(proposal.value)(proposal.data);
      require(success, string(retdata));
    } else {
      // do not
      payouts[0] = 0; payouts[1] = 1;
      conditionalTokens.reportPayouts(proposalHash, payouts);
    }

    delete proposedTransactions[proposalHash];

    emit TransactionProposalResolved(
      proposalHash,
      proposal.availableTime,
      proposal.to,
      execute
    );
  }

  event EpochPassed(
    uint indexed epochEndTime,
    uint timeResolved,
    uint resultStonkPrice
  );

  function poke() external payable {
    uint[] memory payouts = new uint[](2);
    address exchange = address(uniswapExchange);
    uint currentStonkPrice = uint(1 ether).mul(exchange.balance) / balanceOf(exchange);
    uint loPrice = lastStonkPrice / 2;
    uint hiPrice = loPrice.add(lastStonkPrice);
    if (currentStonkPrice < loPrice) {
      payouts[0] = 1;
      payouts[1] = 0;
    } else if (currentStonkPrice > hiPrice) {
      payouts[0] = 0;
      payouts[1] = 1;
    } else {
      payouts[0] = hiPrice - currentStonkPrice;
      payouts[1] = currentStonkPrice - loPrice;
    }

    uint nextTime = nextMarketCapPollTime;
    while (nextTime <= now) {
      bytes32 pollConditionId = CTHelpers.getConditionId(
        address(this),
        bytes32(nextTime),
        2
      );
      if (conditionalTokens.getOutcomeSlotCount(pollConditionId) > 0) {
        conditionalTokens.reportPayouts(bytes32(nextTime), payouts);
      }
      emit EpochPassed(nextTime, now, currentStonkPrice);
      nextTime = nextTime.add(EPOCH_PERIOD);
    }
    nextMarketCapPollTime = nextTime;
    lastStonkPrice = currentStonkPrice;
  }

  function() external payable {}
}
