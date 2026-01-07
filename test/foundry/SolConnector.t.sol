// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { SolanaMock } from "./mocks/SolanaMock.sol";
import { SolConnector } from "../../contracts/SolConnector.sol";
import { SolConnectorMock } from "./mocks/SolConnectorMock.sol";
import { LedgerMock } from "./mocks/LedgerMock.sol";
import { MsgCodec } from "../../contracts/library/MsgCodec.sol";

import { IOAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "forge-std/console.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { WithdrawDataSol, Withdraw2ContractV2, ChainType, VaultEnum } from "../../contracts/interface/ILedger.sol";
import { Utils } from "../../contracts/library/Utils.sol";
import { BrokerIndexInterval } from "../../contracts/SolConnector.sol";

contract SolConnectorTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 private solanaEid = 1;
    uint32 private orderlyEid = 2;

    SolanaMock private solanaVaultMock;
    SolConnectorMock private solCC;
    LedgerMock private ledger;

    address private userA = address(0x1);
    address private userB = address(0x2);
    uint256 private initialBalance = 100 ether;

    bytes32 private usdcTokenHash = Utils.calculateStringHash("USDC");
    uint8 private usdcTokenIndex = 1;
    bytes32 private usdtTokenHash = Utils.calculateStringHash("USDT");
    uint8 private usdtTokenIndex = 2;
    bytes32 private solTokenHash = Utils.calculateStringHash("SOL");
    uint8 private solTokenIndex = 255;
    bytes32 private brokerHash = Utils.calculateStringHash("woofi_pro");
    uint16 private brokerIndex = 1;

    uint128 private usdcDecimalsOnSolana = 6;
    uint128 private usdcDecimalsOnOrderly = 6;
    uint128 private usdtDecimalsOnSolana = 6;
    uint128 private usdtDecimalsOnOrderly = 6;

    uint128 private solDecimalsOnSolana = 9;
    uint128 private solDecimalsOnOrderly = 8;

    function setUp() public virtual override {
        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);

        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        // deploy proxy
        address solanaVaultMockImpl = address(new SolanaMock());
        address solCCImpl = address(new SolConnectorMock());
        ERC1967Proxy solanaVaultProxy = new ERC1967Proxy(solanaVaultMockImpl, "");
        ERC1967Proxy solCCProxy = new ERC1967Proxy(solCCImpl, "");
        solanaVaultMock = SolanaMock(address(solanaVaultProxy));
        solCC = SolConnectorMock(payable(address(solCCProxy)));

        vm.deal(address(solCC), 1 ether);

        solanaVaultMock.initialize(address(endpoints[solanaEid]), address(this), orderlyEid);
        solCC.initialize(address(endpoints[orderlyEid]), address(this), solanaEid);

        // deploy ledger
        ledger = new LedgerMock(address(solCC));

        solCC.setLedger(address(ledger));
        solCC.setSolEid(solanaEid);
        solCC.setOptions(uint8(MsgCodec.MsgType.Withdraw), 200000, 0);

        solCC.setTokenHash2Index(usdcTokenHash, usdcTokenIndex);
        solCC.setTokenHash2Index(usdtTokenHash, usdtTokenIndex);
        solCC.setTokenHash2Index(solTokenHash, solTokenIndex);

        solCC.setTokenDecimalsOnSolana(usdcTokenHash, usdcDecimalsOnSolana);
        solCC.setTokenDecimalsOnSolana(usdtTokenHash, usdtDecimalsOnSolana);
        solCC.setTokenDecimalsOnSolana(solTokenHash, solDecimalsOnSolana);
        solCC.setTokenDecimalsOnOrderly(usdcTokenHash, usdcDecimalsOnOrderly);
        solCC.setTokenDecimalsOnOrderly(usdtTokenHash, usdtDecimalsOnOrderly);
        solCC.setBrokerHash2Index(brokerHash, brokerIndex);

        address[] memory oapps = new address[](2);
        oapps[0] = address(solanaVaultMock);
        oapps[1] = address(solCC);
        this.wireOApps(oapps);
    }

    function test_constructor() public {
        assertEq(solanaVaultMock.owner(), address(this));
        assertEq(solCC.owner(), address(this));
        assertEq(address(solanaVaultMock.endpoint()), address(endpoints[solanaEid]));
        assertEq(address(solCC.endpoint()), address(endpoints[orderlyEid]));
    }

    function test_deposit() public {
        bytes32 accountId = bytes32(uint256(1));
        bytes32 userAddress = bytes32(uint256(3));
        bytes32 tokenHash = bytes32(uint256(4));
        uint64 chainId = 1;
        uint64 tokenAmount = 100;

        vm.expectEmit(true, true, true, true);
        emit SolanaMock.DepositReceived(accountId, brokerHash, tokenHash, chainId, tokenAmount);

        solanaVaultMock.deposit{ value: 1 ether }(accountId, brokerHash, userAddress, tokenHash, chainId, tokenAmount);

        assertEq(solanaVaultMock.depositNonce(), 1);
    }

    function test_receive_deposit() public {
        // TODO: Test receive deposit
    }

    function test_withdraw_usdc() public {
        WithdrawDataSol memory withdrawData = WithdrawDataSol({
            tokenAmount: 100,
            fee: 1,
            chainId: 1,
            accountId: bytes32(uint256(1)),
            r: bytes32(0),
            s: bytes32(0),
            sender: bytes32(uint256(2)),
            receiver: bytes32(uint256(3)),
            withdrawNonce: 1,
            timestamp: uint64(block.timestamp),
            brokerId: "woofi_pro",
            tokenSymbol: "USDC"
        });

        vm.prank(address(ledger));
        solCC.mockWithdraw(withdrawData);
    }

    function test_setLedger() public {
        address newLedger = address(0x123);
        solCC.setLedger(newLedger);
        assertEq(address(solCC.ledger()), newLedger);
    }

    function test_setLedger_onlyOwner() public {
        address newLedger = address(0x123);
        vm.prank(userA);
        // expect revert with error
        // revert OwnableUnauthorizedAccount(_msgSender());
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), userA));
        solCC.setLedger(newLedger);
    }

    function test_setSolEid() public {
        uint32 newEid = 5;
        solCC.setSolEid(newEid);
        assertEq(solCC.solEid(), newEid);
    }

    function test_setSolEid_onlyOwner() public {
        uint32 newEid = 5;
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), userA));
        solCC.setSolEid(newEid);
    }

    function test_setOptions() public {
        uint8 msgType = 1;
        uint128 gas = 200000;
        uint128 value = 0;
        solCC.setOptions(msgType, gas, value);
        (uint128 setGas, uint128 setValue) = solCC.msgOptions(msgType);
        assertEq(setGas, gas);
        assertEq(setValue, value);
    }

    function test_setOptions_onlyOwner() public {
        uint8 msgType = 1;
        uint128 gas = 200000;
        uint128 value = 0;
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), userA));
        solCC.setOptions(msgType, gas, value);
    }

    function test_setOrderDelivery() public {
        bool newOrderDelivery = false;
        uint64 newInboundNonce = 5;
        vm.expectEmit(true, true, true, true);
        emit SolConnector.SetOrderDelivery(newOrderDelivery, newInboundNonce);
        solCC.setOrderDelivery(newOrderDelivery, newInboundNonce);
        assertEq(solCC.orderDelivery(), newOrderDelivery);
        assertEq(solCC.inboundNonce(), newInboundNonce);
    }

    function test_setOrderDelivery_onlyOwner() public {
        bool newOrderDelivery = false;
        uint64 newInboundNonce = 5;
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), userA));
        solCC.setOrderDelivery(newOrderDelivery, newInboundNonce);
    }

    function test_withdraw_onlyLedger() public {
        WithdrawDataSol memory withdrawData = WithdrawDataSol({
            tokenAmount: 100,
            fee: 1,
            chainId: 1,
            accountId: bytes32(uint256(1)),
            r: bytes32(0),
            s: bytes32(0),
            sender: bytes32(uint256(2)),
            receiver: bytes32(uint256(3)),
            withdrawNonce: 1,
            timestamp: uint64(block.timestamp),
            brokerId: "testBroker",
            tokenSymbol: "TEST"
        });

        vm.prank(userA);
        vm.expectRevert("Only ledger can call this function");
        solCC.withdraw(withdrawData);
    }

    function test_withdraw_usdt() public {
        WithdrawDataSol memory withdrawData = WithdrawDataSol({
            tokenAmount: 100,
            fee: 1,
            chainId: 1,
            accountId: bytes32(uint256(1)),
            r: bytes32(0),
            s: bytes32(0),
            sender: bytes32(uint256(2)),
            receiver: bytes32(uint256(3)),
            withdrawNonce: 1,
            timestamp: uint64(block.timestamp),
            brokerId: "woofi_pro",
            tokenSymbol: "USDT"
        });

        ledger.mockWithdraw(withdrawData);
    }

    function test_withdraw_contractv2() public {
        Withdraw2ContractV2 memory data = Withdraw2ContractV2({
            tokenAmount: 100,
            fee: 1,
            senderChainType: ChainType.EVM,
            receiverChainType: ChainType.SOL,
            chainId: 901901901,
            accountId: keccak256("accountId"),
            vaultType: VaultEnum.Ceffu,
            sender: Utils.toBytes32(address(123)),
            withdrawNonce: 11,
            receiver: keccak256("receiver"),
            timestamp: 1234,
            brokerHash: keccak256("woofi_pro"),
            tokenHash: keccak256("USDC"),
            clientId: 12
        });
        ledger.mockWithdraw2ContractV2(data);
    }

    function test_withdraw_contractv2_with_wrong_chaintype() public {
        Withdraw2ContractV2 memory data = Withdraw2ContractV2({
            tokenAmount: 100,
            fee: 1,
            senderChainType: ChainType.EVM,
            receiverChainType: ChainType.EVM,
            chainId: 901901901,
            accountId: keccak256("accountId"),
            vaultType: VaultEnum.Ceffu,
            sender: Utils.toBytes32(address(123)),
            withdrawNonce: 11,
            receiver: keccak256("receiver"),
            timestamp: 1234,
            brokerHash: keccak256("woofi_pro"),
            tokenHash: keccak256("USDC"),
            clientId: 12
        });
        vm.expectRevert("Wrong receiver chain type");
        ledger.mockWithdraw2ContractV2(data);
    }

    function test_setSolConnector() public {
        address newSolConnector = address(0x456);
        ledger.setSolConnector(newSolConnector);
        assertEq(address(ledger.solConnector()), newSolConnector);
    }

    function test_setBrokerIndex() public {
        address brokerManager1 = address(bytes20(keccak256("brokerManager1")));

        solCC.grantRole(solCC.BROKER_MANAGER_ROLE(), brokerManager1);
        assertEq(solCC.hasRole(solCC.BROKER_MANAGER_ROLE(), brokerManager1), true);

        BrokerIndexInterval memory interval1 = BrokerIndexInterval(18000, 18100);
        solCC.setBrokerIndexInterval(brokerManager1, interval1.start, interval1.end);

        bytes32 testBroker1 = keccak256("testBroker1");

        vm.startPrank(brokerManager1);
        vm.expectRevert("Broker index out of broker manager interval");
        solCC.setBrokerHash2Index(testBroker1, 17999);
        vm.expectRevert("Broker index out of broker manager interval");
        solCC.setBrokerHash2Index(testBroker1, 18100);
        vm.expectEmit();
        emit SolConnector.SetBrokerHashToIndex(testBroker1, 0, 18001);
        solCC.setBrokerHash2Index(testBroker1, 18001);

        bytes32 testBroker2 = keccak256("testBroker2");
        vm.expectRevert("Broker index already used");
        solCC.setBrokerHash2Index(testBroker2, 18001);

        vm.expectRevert("Broker already set");
        solCC.setBrokerHash2Index(testBroker1, 18000);
        vm.stopPrank();

        vm.expectEmit();
        emit SolConnector.SetBrokerHashToIndex(testBroker1, 18001, 123);
        solCC.resetBrokerHash2Index(testBroker1, 123);

        assertEq(solCC.brokerIndex2Hash(18001), bytes32(0));
        assertEq(solCC.brokerIndex2Hash(123), testBroker1);
        assertEq(solCC.brokerHash2Index(testBroker1), 123);

        address brokerManager2 = address(bytes20(keccak256("brokerManager2")));

        vm.startPrank(address(ledger));
        vm.expectRevert("Not broker manager");
        solCC.setBrokerFromLedger(brokerManager2, testBroker2, 18002);
        vm.expectEmit();
        emit SolConnector.SetBrokerHashToIndex(testBroker2, 0, 18002);
        solCC.setBrokerFromLedger(brokerManager1, testBroker2, 18002);
        vm.stopPrank();

        vm.expectRevert("Only ledger can call this function");
        solCC.setBrokerFromLedger(brokerManager1, testBroker2, 18002);
    }
}
