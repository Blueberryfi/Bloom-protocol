// SPDX-License-Identifier: BUSL-1.1
/*
██████╗░██╗░░░░░░█████╗░░█████╗░███╗░░░███╗
██╔══██╗██║░░░░░██╔══██╗██╔══██╗████╗░████║
██████╦╝██║░░░░░██║░░██║██║░░██║██╔████╔██║
██╔══██╗██║░░░░░██║░░██║██║░░██║██║╚██╔╝██║
██████╦╝███████╗╚█████╔╝╚█████╔╝██║░╚═╝░██║
╚═════╝░╚══════╝░╚════╝░░╚════╝░╚═╝░░░░░╚═╝
*/

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";

import {MockERC20, ERC20} from "./mock/MockERC20.sol";
import {MockBloomPool} from "./mock/MockBloomPool.sol";
import {MockSwapFacility} from "./mock/MockSwapFacility.sol";
import {MockOracle} from "./mock/MockOracle.sol";

import {EmergencyHandler, IEmergencyHandler} from "src/EmergencyHandler.sol";
import {ExchangeRateRegistry} from "src/helpers/ExchangeRateRegistry.sol";
import {AssetCommitment} from "src/lib/CommitmentsLib.sol";

import {IBloomPool} from "src/interfaces/IBloomPool.sol";

contract EmergencyHandlerTest is Test {
    address internal multisig = makeAddr("multisig");
    MockERC20 internal stableToken;
    MockERC20 internal billyToken;
    MockBloomPool internal pool;
    MockSwapFacility internal swap;
    MockOracle internal stableOracle;
    MockOracle internal billyOracle;
    
    ExchangeRateRegistry internal registry;
    EmergencyHandler internal handler;

    function setUp() public {
        stableToken = new MockERC20(6);
        billyToken = new MockERC20(18);
        stableOracle = new MockOracle(8);
        billyOracle = new MockOracle(8);
        swap = new MockSwapFacility(stableToken, billyToken, stableOracle, billyOracle);
        pool = new MockBloomPool(address(stableToken), address(billyToken), address(swap));
        pool.setCommitPhaseEnd(block.timestamp + 100000);
        address factory = makeAddr("factory");
        registry = new ExchangeRateRegistry(multisig, factory);

        vm.startPrank(multisig);
        registry.registerToken(IBloomPool(address(pool)));
        handler = new EmergencyHandler(registry);
        vm.stopPrank();
    }

    function test_getRegistry() public {
        assertEq(address(registry), address(handler.REGISTRY()));
    }

    function test_redemptionInfo() public {
        _registerPool(stableToken, 100e6);

        (address token, uint256 rate, ) = handler.redemptionInfo(address(pool));
        assertEq(token, address(stableToken));
        assertEq(rate, 1e8);
    }

    function test_borrowerClaimStatus() public {
        _registerPool(billyToken, 100e6);

        assertEq(handler.borrowerClaimStatus(address(pool),0), false);
    }

    function test_redeemLender() public {
        address lender = makeAddr("lender");
        MockERC20(address(pool)).mint(lender, 100e6);

        _registerPool(stableToken, 100e6);

        vm.startPrank(lender);
        handler.redeem(IBloomPool(address(pool)));

        assertEq(stableToken.balanceOf(lender), 100e6);
        assertEq(ERC20(address(pool)).balanceOf(lender), 0);
    }

    function test_redeemBorrower() public {
        address borrower = makeAddr("borrower");
        _registerPool(billyToken, 100e18);

        uint256 id = 0;

        MockBloomPool.AssetCommitment memory commitment = MockBloomPool.AssetCommitment({
            owner: borrower,
            committedAmount: 100e6,
            cumulativeAmountEnd: 100e6
        });

        pool.setBorrowerCommitment(id, commitment);
        
        vm.startPrank(borrower);
        handler.redeem(IBloomPool(address(pool)), id);
        vm.stopPrank();

        assertEq(billyToken.balanceOf(borrower), 100e18);
        assertEq(billyToken.balanceOf(address(handler)), 0);
    }

    function _registerPool(MockERC20 token, uint256 amount) internal {
        pool.setState(MockBloomPool.State.EmergencyExit);
        pool.setEmergencyHandler(address(handler));

        if (token == stableToken) {
            stableOracle.setAnswer(1e8);
            stableToken.mint(address(handler), amount);

            vm.startPrank(address(pool));
            handler.registerPool(stableOracle, address(stableToken));
            vm.stopPrank();
        } else {
            billyOracle.setAnswer(1e8);
            billyToken.mint(address(handler), amount);

            vm.startPrank(address(pool));
            handler.registerPool(billyOracle, address(billyToken));
            vm.stopPrank();
        }        
    }
    
}