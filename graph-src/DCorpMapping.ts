import { log } from '@graphprotocol/graph-ts'

import {
  TransactionProposed,
  TransactionProposalResolved,
} from '../generated/DCorp/DCorp'
import { TransactionProposal } from '../generated/schema'

export function onTransactionProposed(event: TransactionProposed): void {
  let proposal = new TransactionProposal(event.params.proposalHash.toHexString());
  proposal.isPendingResolution = true;
  proposal.availableTime = event.params.availableTime
  proposal.to = event.params.to
  proposal.value = event.params.value
  proposal.data = event.params.data
  proposal.fpmm = event.params.fpmm
  proposal.save();
}

export function onTransactionProposalResolved(event: TransactionProposalResolved): void {
  let id = event.params.proposalHash.toHexString();
  let proposal = TransactionProposal.load(id);
  if (proposal == null) {
    log.error('missing TransactionProposal {}', [id])
  }

  proposal.isPendingResolution = false;
  proposal.executed = event.params.executed;
  proposal.save();
}
