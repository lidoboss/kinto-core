// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core-script/utils/MigrationHelper.sol";

interface IUpgradeExecutor {
    function initialize(address admin, address[] memory executors) external;
    function execute(address upgrade, bytes memory upgradeCallData) external payable;
    function executeCall(address target, bytes memory targetCallData) external payable;
    function hasRole(bytes32 role, address account) external view returns (bool);
}

contract KintoMigration44DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();

        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        console.log("Running on chain: ", vm.toString(block.chainid));
        console.log("Executing from address", msg.sender);
        console.log("Deployer is: ", vm.addr(deployerPrivateKey));

        IUpgradeExecutor upgradeExecutor = IUpgradeExecutor(0x88e03D41a6EAA9A0B93B0e2d6F1B34619cC4319b);

        bytes32 EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
        if (!upgradeExecutor.hasRole(EXECUTOR_ROLE, vm.addr(deployerPrivateKey))) {
            revert("Sender does not have EXECUTOR_ROLE");
        }
        if (!upgradeExecutor.hasRole(EXECUTOR_ROLE, vm.envAddress("LEDGER_ADMIN"))) {
            revert("ADMIN_LEDGER does not have EXECUTOR_ROLE");
        }

        bytes memory upgradeCallData =
            abi.encodeWithSignature("revokeRole(bytes32,address)", EXECUTOR_ROLE, vm.addr(deployerPrivateKey));
        vm.broadcast(deployerPrivateKey);
        upgradeExecutor.executeCall(address(upgradeExecutor), upgradeCallData);

        assertTrue(!upgradeExecutor.hasRole(EXECUTOR_ROLE, vm.addr(deployerPrivateKey)));
    }
}
