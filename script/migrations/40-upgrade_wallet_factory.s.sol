// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/bridger/BridgerL2.sol";
import "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration40DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();

        bytes memory bytecode = abi.encodePacked(
            type(KintoWalletFactory).creationCode, abi.encode(_getChainDeployment("KintoWalletV6-impl"))
        );
        _deployImplementationAndUpgrade("KintoWalletFactory", "V12", bytecode);
    }
}
