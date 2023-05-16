// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {SafeCastLib} from "solady/utils/SafeCastLib.sol";

struct AssetCommitment {
    address owner;
    uint128 commitedAmount;
    uint128 cumulativeAmountEnd;
}

struct Commitments {
    mapping(uint256 => AssetCommitment) commitments;
    uint64 commitmentCount;
    uint192 totalAssetsCommited;
}

/// @author philogy <https://github.com/philogy>
library CommitmentsLib {
    using SafeCastLib for uint256;

    error NonexistentCommit();

    function add(Commitments storage commitments, address owner, uint256 amount)
        internal
        returns (uint256 newCommitmendId, uint256 cumulativeAmountEnd)
    {
        uint256 commitmentCount = commitments.commitmentCount;
        unchecked {
            newCommitmendId = commitmentCount++;
        }
        cumulativeAmountEnd = commitments.totalAssetsCommited + amount;
        commitments.commitments[newCommitmendId] = AssetCommitment({
            owner: owner,
            commitedAmount: uint128(amount),
            cumulativeAmountEnd: cumulativeAmountEnd.toUint128()
        });
        commitments.commitmentCount = commitmentCount.toUint64();
        // If safe cast to uint128 did not fail cast to uint192 cannot truncate.
        commitments.totalAssetsCommited = uint192(cumulativeAmountEnd);
    }

    function getAmountSplit(AssetCommitment storage commitment, uint256 totalIncludedAmount)
        internal
        view
        returns (uint256 includedAmount, uint256 excludedAmount)
    {
        uint256 commitedAmount = commitment.commitedAmount;
        uint256 cumulativeAmountEnd = commitment.cumulativeAmountEnd;
        if (totalIncludedAmount >= cumulativeAmountEnd) {
            includedAmount = commitedAmount;
            excludedAmount = 0;
        } else {
            uint256 cumulativeAmountStart = cumulativeAmountEnd - commitedAmount;
            if (cumulativeAmountStart > totalIncludedAmount) {
                includedAmount = 0;
                excludedAmount = commitedAmount;
            } else {
                unchecked {
                    includedAmount = totalIncludedAmount - cumulativeAmountStart;
                    excludedAmount = commitedAmount - includedAmount;
                }
            }
        }
    }

    function get(Commitments storage commitments, uint256 id) internal view returns (AssetCommitment storage) {
        if (id >= commitments.commitmentCount) {
            revert NonexistentCommit();
        }
        return commitments.commitments[id];
    }
}