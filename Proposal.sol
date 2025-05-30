// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Params.sol";
import "./Validators.sol";

contract Proposal is Params {
    // How long a proposal will exist
    uint256 public proposalLastingPeriod;

    // record
    mapping(address => bool) public pass;
    mapping(address => bool) public lastProposalActive;
    uint256 public proposalCount ;
    struct ProposalInfo {
        // who propose this proposal
        address proposer;
        // propose who to be a validator
        address dst;
        // optional detail info of proposal
        string details;
        // time create proposal
        uint256 createTime;
        //
        // vote info
        //
        // number agree this proposal
        uint16 agree;
        // number reject this proposal
        uint16 reject;
        // means you can get proposal of current vote.
        bool resultExist;
    }

    struct VoteInfo {
        address voter;
        uint256 voteTime;
        bool auth;
    }

    mapping(uint256 => ProposalInfo) public proposals;
    mapping(address => mapping(uint256 => VoteInfo)) public votes;

    Validators validators;

    event LogCreateProposal(
        uint256 indexed id,
        address indexed proposer,
        address indexed dst,
        uint256 time
    );
    event LogVote(
        uint256 indexed id,
        address indexed voter,
        bool auth,
        uint256 time
    );
    event LogPassProposal(
        uint256 indexed id,
        address indexed dst,
        uint256 time
    );
    event LogRejectProposal(
        uint256 indexed id,
        address indexed dst,
        uint256 time
    );
    event LogSetUnpassed(address indexed val, uint256 time);

    modifier onlyValidator() {
        require(validators.isActiveValidator(msg.sender), "Validator only");
        _;
    }

    function initialize(address[] calldata vals) external onlyNotInitialized {
        proposalLastingPeriod = 7 days;
        validators = Validators(ValidatorContractAddr);

        for (uint256 i = 0; i < vals.length; i++) {
            require(vals[i] != address(0), "Invalid validator address");
            pass[vals[i]] = true;
        }

        initialized = true;
    }

    function createProposal(address dst, string calldata details)
        external
        returns (bool)
    {
        //require(!pass[dst], "Dst already passed, You can start staking"); 
        require(!lastProposalActive[dst], "Already active proposal");
        // generate proposal id
        uint256 id = proposalCount ;
        require(bytes(details).length <= 3000, "Details too long");
        require(proposals[id].createTime == 0, "Proposal already exists");

        ProposalInfo memory proposal;
        proposal.proposer = msg.sender;
        proposal.dst = dst;
        proposal.details = details;
        proposal.createTime = block.timestamp;
        lastProposalActive[dst] = true;
        proposals[id] = proposal;
        emit LogCreateProposal(id, msg.sender, dst, block.timestamp);
        proposalCount += 1;
        return true;
    }

    function voteProposal(uint256 id, bool auth)
        external
        onlyValidator
        returns (bool)
    {
        require(proposals[id].createTime != 0, "Proposal not exist");
        require(
            votes[msg.sender][id].voteTime == 0,
            "You can't vote for a proposal twice"
        );
        require(
            block.timestamp < proposals[id].createTime + proposalLastingPeriod,
            "Proposal expired"
        );

        votes[msg.sender][id].voteTime = block.timestamp;
        votes[msg.sender][id].voter = msg.sender;
        votes[msg.sender][id].auth = auth;
        emit LogVote(id, msg.sender, auth, block.timestamp);

        // update dst status if proposal is passed
        if (auth) {
            proposals[id].agree = proposals[id].agree + 1;
        } else {
            proposals[id].reject = proposals[id].reject + 1;
        }

        //if (pass[proposals[id].dst] || proposals[id].resultExist) {
        if(!lastProposalActive[proposals[id].dst] || proposals[id].resultExist) {
            // do nothing if dst already passed or rejected.
            return true;
        }

        if (
            proposals[id].agree >=
            validators.getActiveValidators().length / 2 + 1
        ) {
            pass[proposals[id].dst] = true;
            proposals[id].resultExist = true;            
            // try to reactive validator if it isn't the first time
            validators.tryReactive(proposals[id].dst);
            lastProposalActive[proposals[id].dst] = false;
            emit LogPassProposal(id, proposals[id].dst, block.timestamp);

            return true;
        }

        if (
            proposals[id].reject >=
            (validators.getActiveValidators().length / 2) + 1
        ) {
            proposals[id].resultExist = true;
            lastProposalActive[proposals[id].dst] = false;
            emit LogRejectProposal(id, proposals[id].dst, block.timestamp);
        }

        return true;
    }

    function setUnpassed(address val)
        external
        onlyValidatorsContract
        returns (bool)
    {
        // set validator unpass
        pass[val] = false;
        lastProposalActive[val] = false;
        emit LogSetUnpassed(val, block.timestamp);
        return true;
    }
}
