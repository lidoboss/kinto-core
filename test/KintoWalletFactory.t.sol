// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import '../src/wallet/KintoWallet.sol';
import '../src/wallet/KintoWalletFactory.sol';
import '../src/paymasters/SponsorPaymaster.sol';
import '../src/KintoID.sol';
import {UserOp} from './helpers/UserOp.sol';
import {UUPSProxy} from './helpers/UUPSProxy.sol';
import {KYCSignature} from './helpers/KYCSignature.sol';
import {Create2Helper} from './helpers/Create2Helper.sol';

import '@aa/interfaces/IAccount.sol';
import '@aa/interfaces/INonceManager.sol';
import '@aa/interfaces/IEntryPoint.sol';
import '@aa/core/EntryPoint.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';
import { UpgradeableBeacon } from '@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol';
import {SignatureChecker} from '@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';

import 'forge-std/Test.sol';
import 'forge-std/console.sol';

contract KintoWalletV2 is KintoWallet {
  constructor(IEntryPoint _entryPoint, IKintoID _kintoID) KintoWallet(_entryPoint, _kintoID) {}

  function walletFunction() public pure returns (uint256) {
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

contract KintoWalletFactoryV2 is KintoWalletFactory {
  constructor(KintoWallet _impl) KintoWalletFactory(_impl) {

  }
  function newFunction() public pure returns (uint256) {
      return 1;
  }
}

contract KintoWalletFactoryTest is Create2Helper, UserOp, KYCSignature {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    EntryPoint _entryPoint;
    KintoWalletFactory _walletFactory;
    KintoWalletFactory _walletFactoryI;
    KintoWalletFactoryV2 _walletFactoryv2;
    KintoID _implementation;
    KintoID _kintoIDv1;
    SponsorPaymaster _paymaster;

    KintoWallet _kintoWalletImpl;
    IKintoWallet _kintoWalletv1;
    KintoWalletV2 _kintoWalletv2;
    UUPSProxy _proxy;
    UUPSProxy _proxys;
    UpgradeableBeacon _beacon;

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
        _implementation = new KintoID{salt: 0}();
        // deploy _proxy contract and point it to _implementation
        _proxy = new UUPSProxy{salt: 0}(address(_implementation), '');
        // wrap in ABI to support easier calls
        _kintoIDv1 = KintoID(address(_proxy));
        // Initialize _proxy
        _kintoIDv1.initialize();
        _kintoIDv1.grantRole(_kintoIDv1.KYC_PROVIDER_ROLE(), _kycProvider);
        _entryPoint = new EntryPoint{salt: 0}();
        // Deploy wallet implementation
        _kintoWalletImpl = new KintoWallet{salt: 0}(_entryPoint, _kintoIDv1);
        // Deploy beacon
        _beacon = new UpgradeableBeacon(address(_kintoWalletImpl));
        //Deploy wallet factory implementation
        _walletFactoryI = new KintoWalletFactory{salt: 0}(KintoWallet(payable(_kintoWalletImpl)));
        _proxy = new UUPSProxy{salt: 0}(address(_walletFactoryI), '');
        _walletFactory = KintoWalletFactory(address(_proxy));
        _walletFactory.initialize(_kintoIDv1);
        // Set the wallet factory in the entry point
        _entryPoint.setWalletFactory(address(_walletFactory));
        // Mint an nft to the owner
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(
            _kintoIDv1, _owner, _owner, 1, block.timestamp + 1000);
        uint16[] memory traits = new uint16[](0);
        vm.startPrank(_kycProvider);
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        vm.stopPrank();
        vm.startPrank(_owner);
        // deploy the paymaster
        _paymaster = new SponsorPaymaster{salt: 0}(_entryPoint);
        // deploy _proxy contract and point it to _implementation
        _proxys = new UUPSProxy(address(_paymaster), '');
        // wrap in ABI to support easier calls
        _paymaster = SponsorPaymaster(address(_proxys));
        // Initialize proxy
        _paymaster.initialize(_owner);
        vm.stopPrank();
    }

    function testUp() public {
        assertEq(_walletFactory.factoryWalletVersion(), 1);
    }

    /* ============ Upgrade Tests ============ */

    function testOwnerCanUpgradeFactory() public {
        vm.startPrank(_owner);
        KintoWalletFactoryV2 _implementationV2 = new KintoWalletFactoryV2(_kintoWalletImpl);
        _walletFactory.upgradeTo(address(_implementationV2));
        // re-wrap the _proxy
        _walletFactoryv2 = KintoWalletFactoryV2(address(_proxy));
        assertEq(_walletFactoryv2.newFunction(), 1);
        vm.stopPrank();
    }

    function testFailOthersCannotUpgradeFactory() public {
        KintoWalletFactoryV2 _implementationV2 = new KintoWalletFactoryV2(_kintoWalletImpl);
        _kintoIDv1.upgradeTo(address(_implementationV2));
        // re-wrap the _proxy
        _walletFactoryv2 = KintoWalletFactoryV2(address(_proxy));
        assertEq(_walletFactoryv2.newFunction(), 1);
    }

    function testAllWalletsUpgrade() public {
        vm.startPrank(_owner);

        // Deploy wallet implementation
        _kintoWalletImpl = new KintoWalletV2(_entryPoint, _kintoIDv1);

        // deploy walletv1 through wallet factory and initializes it
        _kintoWalletv1 = _walletFactory.createAccount(_owner, _owner, 0);

        // Upgrade all implementations
        _walletFactory.upgradeAllWalletImplementations(_kintoWalletImpl);

        KintoWalletV2 walletV2 = KintoWalletV2(payable(address(_kintoWalletv1)));
        assertEq(walletV2.walletFunction(), 1);
        vm.stopPrank();
    }

    function testFailOthersCannotUpgradeWallets() public {
        // Deploy wallet implementation
        _kintoWalletImpl = new KintoWalletV2(_entryPoint, _kintoIDv1);
        // deploy walletv1 through wallet factory and initializes it
        _kintoWalletv1 = _walletFactory.createAccount(_owner, _owner, 0);
        // Upgrade all implementations
        _walletFactory.upgradeAllWalletImplementations(_kintoWalletImpl);
    }

    /* ============ Deploy Tests ============ */
    function testDeployCustomContract() public {
        // _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_owner);
        address computed = _walletFactory.getContractAddress(
          bytes32(0), keccak256(abi.encodePacked(type(Counter).creationCode)));
        address created = _walletFactory.deployContract(0,
            abi.encodePacked(type(Counter).creationCode), bytes32(0));
        assertEq(computed, created);
        assertEq(Counter(created).count(), 0);
        Counter(created).increment();
        assertEq(Counter(created).count(), 1);
        vm.stopPrank();
    }

    /* ============ Helpers ============ */

    function _setPaymasterForContract(address _contract) private {
        vm.startPrank(_owner);
        vm.deal(_owner, 1e20);
        // We add the deposit to the counter contract in the paymaster
        _paymaster.addDepositFor{value: 5e18}(address(_contract));
        vm.stopPrank();
    }
}
