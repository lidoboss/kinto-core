// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import '../src/wallet/KintoWallet.sol';
import '../src/wallet/KintoWalletFactory.sol';
import '../src/paymasters/SponsorPaymaster.sol';
import '../src/KintoID.sol';
import {UserOp} from './helpers/UserOp.sol';
import {KYCSignature} from './helpers/KYCSignature.sol';

import '@aa/interfaces/IAccount.sol';
import '@aa/interfaces/INonceManager.sol';
import '@aa/interfaces/IEntryPoint.sol';
import '@aa/core/EntryPoint.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';
import {SignatureChecker} from '@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';

import 'forge-std/Test.sol';
import 'forge-std/console.sol';

contract UUPSProxy is ERC1967Proxy {
    constructor(address __implementation, bytes memory _data)
        ERC1967Proxy(__implementation, _data)
    {}
}

contract KintoWalletv2 is KintoWallet {
  constructor(IEntryPoint _entryPoint, IKintoID _kintoID) KintoWallet(_entryPoint, _kintoID) {}

  function newFunction() public pure returns (uint256) {
      return 1;
  }
}

contract Counter {

    uint256 public count;

    constructor() {
      count = 0;
    }

    function increment() public {
        count += 1;
    }
}

contract KintoWalletTest is UserOp, KYCSignature {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    EntryPoint _entryPoint;
    KintoWalletFactory _walletFactory;
    KintoID _implementation;
    KintoID _kintoIDv1;
    SponsorPaymaster _paymaster;

    KintoWallet _kintoWalletv1;
    KintoWalletv2 _kintoWalletv2;
    UUPSProxy _proxy;

    uint256 _chainID = 1;

    address payable _owner = payable(vm.addr(1));
    address _secondowner = address(2);
    address _user = vm.addr(3);
    address _user2 = address(4);
    address _upgrader = address(5);
    address _kycProvider = address(6);


    function setUp() public {
        vm.chainId(_chainID);
        vm.startPrank(address(1));
        _owner.transfer(1e18);
        vm.stopPrank();
        vm.startPrank(_owner);
        // Deploy Kinto ID
        _implementation = new KintoID();
        // deploy _proxy contract and point it to _implementation
        _proxy = new UUPSProxy(address(_implementation), '');
        // wrap in ABI to support easier calls
        _kintoIDv1 = KintoID(address(_proxy));
        // Initialize _proxy
        _kintoIDv1.initialize();
        _kintoIDv1.grantRole(_kintoIDv1.KYC_PROVIDER_ROLE(), _kycProvider);
        _entryPoint = new EntryPoint{salt: 0}();
        //Deploy wallet factory
        _walletFactory = new KintoWalletFactory(_entryPoint, _kintoIDv1);
        // Mint an nft to the owner
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoIDv1, _owner, _owner, 1, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](0);
        vm.startPrank(_kycProvider);
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        vm.stopPrank();
        vm.startPrank(_owner);
        // deploy walletv1 through wallet factory and initializes it
        _kintoWalletv1 = _walletFactory.createAccount(_owner, 0);
        // deploy the paymaster
        _paymaster = new SponsorPaymaster(_entryPoint);
        vm.stopPrank();
    }

    function testUp() public {
        assertEq(address(_kintoWalletv1.entryPoint()), address(_entryPoint));
        assertEq(_kintoWalletv1.owners(0), _owner);
    }

    // Upgrade Tests

    function testOwnerCanUpgrade() public {
        vm.startPrank(_owner);
        vm.deal(_owner, 1e20);
        _paymaster.addDepositFor{value: 5e18}(address(_kintoWalletv1));
        KintoWalletv2 _implementationV2 = new KintoWalletv2(_entryPoint, _kintoIDv1);
        UserOperation memory userOp = this.createUserOperationWithPaymaster(address(_kintoWalletv1), 1, address(_kintoWalletv1), 0, abi.encodeWithSignature('upgradeTo(address)',address(_implementationV2)), address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        // _kintoWalletv1.upgradeTo(address(_implementationV2));
        _kintoWalletv2 = KintoWalletv2(payable(_kintoWalletv1));
        assertEq(_kintoWalletv2.newFunction(), 1);
        vm.stopPrank();
    }

    function testFailOthersCannotUpgrade() public {
        vm.startPrank(_owner);
        vm.deal(_owner, 1e20);
        _paymaster.addDepositFor{value: 5e18}(address(_kintoWalletv1));
        KintoWalletv2 _implementationV2 = new KintoWalletv2(_entryPoint, _kintoIDv1);
        UserOperation memory userOp = this.createUserOperationWithPaymaster(address(_user), 3, address(_kintoWalletv1), 0, abi.encodeWithSignature('upgradeTo(address)',address(_implementationV2)), address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        // _kintoWalletv1.upgradeTo(address(_implementationV2));
        _kintoWalletv2 = KintoWalletv2(payable(_kintoWalletv1));
        assertEq(_kintoWalletv2.newFunction(), 1);
        vm.stopPrank();
    }

    function testFailSendingTransactionDirectly() public {
        vm.startPrank(_owner);
        // Let's deploy the counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        // Let's send a transaction to the counter contract through our wallet
        UserOperation memory userOp = this.createUserOperation(address(_kintoWalletv1), 1, address(counter), 0, abi.encodeWithSignature('increment()'));
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
        vm.stopPrank();
    }

    function testTransactionViaPaymaster() public {
        vm.startPrank(_owner);
        vm.deal(_owner, 1e20);
        // Let's deploy the counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        // We add the deposit to the counter contract in the paymaster
        _paymaster.addDepositFor{value: 5e18}(address(counter));
        // Let's send a transaction to the counter contract through our wallet
        UserOperation memory userOp = this.createUserOperationWithPaymaster(address(_kintoWalletv1), 1, address(counter), 0, abi.encodeWithSignature('increment()'), address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
        vm.stopPrank();
    }

}
