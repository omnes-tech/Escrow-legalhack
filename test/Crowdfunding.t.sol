// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Crowdfunding, CampaignToken} from "../src/CrowdFunding.sol";
import {Campaign} from "../src/interfaces/ICrowdfunding.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

contract CrowdfundingTest is Test {
    using stdStorage for StdStorage;

    StdStorage stdstoreCrowdfunding;
    Crowdfunding public crowdfunding;
    MockERC20 public token;
    MockERC20 public usdc;
    MockERC20 public usdt;

    
    address public ownerCreator = makeAddr("ownerCreator");
    address public platformWallet = makeAddr("platformWallet");
    address public creatorVault = makeAddr("creatorVault");
    address public investor = makeAddr("investor");
    address public beneficiary = makeAddr("beneficiary");

    string public MAINNET_RPC_URL = vm.envString("BASE_RPC_URL");
    uint256 public mainnetFork;

    // caso queira usar uma carteira sua, comente a linha abaixo e descomente a 34 e 35
    address public ownerPlatform = makeAddr("ownerPlatform");
    // uint256 privateKey = vm.envUint("PRIVATE_KEY");
    // address public ownerPlatform = vm.addr(privateKey);


    // Base Mainnet addresses
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant USDT = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;

    address constant SEQUENCER_UPTIME_FEED = 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433;
    address constant USDC_PRICE_FEED = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
    address constant USDT_PRICE_FEED = 0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9;
    address constant BRL_PRICE_FEED = 0x0b0E64c05083FdF9ED7C5D3d8262c4216eFc9394;
    address constant ETH_PRICE_FEED = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;

    function setUp() public {
        // Create and select fork
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        // Start with owner context
        vm.startPrank(ownerPlatform);

        // Deploy mock tokens
        token = new MockERC20("Official Token", "OT");
        usdc = new MockERC20("USDC Mock", "USDC");
        usdt = new MockERC20("USDT Mock", "USDT");

        // Deploy crowdfunding with owner as initial owner
        crowdfunding = new Crowdfunding(
            address(token), // _officialToken
            ownerPlatform, // _owner
            SEQUENCER_UPTIME_FEED,
            USDC_PRICE_FEED,
            USDT_PRICE_FEED,
            BRL_PRICE_FEED,
            ETH_PRICE_FEED
        );

        // Mint tokens
        token.mint(address(crowdfunding), 1_000_000_000e18); // Mint enough tokens for all tests
        usdc.mint(investor, 1_000_000e6);
        usdt.mint(investor, 1_000_000e6);

        // Allow investor and set limits
        address[] memory allowedInvestors = new address[](1);
        allowedInvestors[0] = investor;
        crowdfunding.setAllowedInvestor(allowedInvestors, true);
        crowdfunding.setAnnualLimit(3400e18); // ~3,400 USD ≈ 20,000 BRL

        // Stop owner context
        vm.stopPrank();

        // Label addresses for better trace output
        vm.label(ownerPlatform, "OwnerPlatform");
        vm.label(ownerCreator, "OwnerCreator");
        vm.label(investor, "Investor");
        vm.label(beneficiary, "Beneficiary");
        vm.label(address(crowdfunding), "Crowdfunding");
        vm.label(address(usdc), "USDC Mock");
        vm.label(address(usdt), "USDT Mock");
        vm.label(address(0), "ETH");

        // Setup approvals
        vm.startPrank(investor);
        usdc.approve(address(crowdfunding), type(uint256).max);
        usdt.approve(address(crowdfunding), type(uint256).max);
        vm.stopPrank();

        // Setup allowed investors and creators
        vm.startPrank(ownerPlatform);
        address[] memory investors = new address[](1);
        investors[0] = investor;
        crowdfunding.setAllowedInvestor(investors, true);

        address[] memory creators = new address[](1);
        creators[0] = ownerCreator;
        crowdfunding.setAllowedCreator(creators);
        vm.stopPrank();
    }

    function test_PriceFeedSequencerCheck() public {
        vm.startPrank(investor);

        // Should not revert as sequencer is up
        uint256 usdcPrice = crowdfunding.getUSDPrice(USDC);
        assertGt(usdcPrice, 0, "USDC price should be > 0");

        // Simulate sequencer down
        vm.mockCall(
            address(SEQUENCER_UPTIME_FEED), // Base Sequencer Feed
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(0, 1, block.timestamp, block.timestamp, 0)
        );

        vm.expectRevert(Crowdfunding.SequencerDown.selector);
        crowdfunding.getUSDPrice(USDC);

        vm.stopPrank();
    }

    function test_StalePrice() public {
        vm.startPrank(investor);

        // Get current price
        uint256 currentPrice = crowdfunding.getUSDPrice(USDC);
        assertGt(currentPrice, 0, "USDC price should be > 0");

        // Warp time forward 25 hours
        vm.warp(block.timestamp + 25 hours);

        // Should revert with stale price
        vm.expectRevert(Crowdfunding.StalePrice.selector);
        crowdfunding.getUSDPrice(USDC);
        console.log("Current price:", currentPrice);

        vm.stopPrank();
    }

    function test_TokenPriceConversions() public {
        vm.startPrank(investor);

        // Get USD prices
        uint256 usdcPrice = crowdfunding.getUSDPrice(USDC);
        uint256 usdtPrice = crowdfunding.getUSDPrice(USDT);

        console.log("USDC/USD Price:", usdcPrice);
        console.log("USDT/USD Price:", usdtPrice);

        // Both should be close to $1 (with 8 decimals)
        assertApproxEqRel(usdcPrice, 1e8, 0.1e18, "USDC price too far from $1");
        assertApproxEqRel(usdtPrice, 1e8, 0.1e18, "USDT price too far from $1");

        vm.stopPrank();
    }

    function test_BRLConversion() public {
        vm.startPrank(investor);

        // Convert 1000 USD to BRL
        uint256 usdAmount = 1000e18; // 1000 USD with 18 decimals
        uint256 brlAmount = crowdfunding.getBRLPrice(usdAmount);

        console.log("1000 USD in BRL:", brlAmount / 1e18);

        // BRL should be > USD (as of 2024)
        assertGt(brlAmount, usdAmount, "BRL should be worth more than USD");

        vm.stopPrank();
    }

    function test_MaxTargetCalculation() public {
        vm.startPrank(investor);

        // Get max target in USDC
        uint256 maxUSDC = crowdfunding.getMaxTargetInToken(USDC);
        console.log("Max USDC target:", maxUSDC / 1e6); // Display in USDC units

        // Get max target in USDT
        uint256 maxUSDT = crowdfunding.getMaxTargetInToken(USDT);
        console.log("Max USDT target:", maxUSDT / 1e6); // Display in USDT units

        // Both should be similar (as both are ~$1)
        assertApproxEqRel(maxUSDC, maxUSDT, 0.1e18, "USDC and USDT max targets too different");

        vm.stopPrank();
    }

    function test_CampaignWithMaxTarget() public {
        uint32 startTime = uint32(block.timestamp + 1 days);
        uint32 endTime = startTime + 30 days;
        uint32 vestingStart = endTime;
        uint32 vestingDuration = 180 days;

        address[] memory leaders = new address[](1);
        leaders[0] = makeAddr("leader1");

        uint256[] memory minContribs = new uint256[](1);
        minContribs[0] = 500e6;

        uint256[] memory carryBPs = new uint256[](1);
        carryBPs[0] = 1000;

        vm.startPrank(ownerPlatform);
        uint256 campaignId = crowdfunding.launchCampaign(
            6700e6, // minTarget (exactly 2/3 of maxTarget)
            10000e6, // maxTarget
            startTime,
            endTime,
            vestingStart,
            vestingDuration,
            USDC,
            address(token),
            500, // 5% platform fee
            platformWallet,
            ownerCreator,
            creatorVault,
            leaders,
            minContribs,
            carryBPs
        );

        assertEq(campaignId, 1, "Campaign ID should be 1");
        vm.stopPrank();
    }

    function test_InvestAndSwap() public {
        // Setup campaign
        uint32 startTime = uint32(block.timestamp + 1 days);
        uint32 endTime = startTime + 30 days;
        uint32 vestingStart = endTime;
        uint32 vestingDuration = 180 days;

        // Setup leader arrays
        address[] memory leaders = new address[](1);
        leaders[0] = makeAddr("leader");

        uint256[] memory minContribs = new uint256[](1);
        minContribs[0] = 500e6; // 500 USDC min contribution

        uint256[] memory carryBPs = new uint256[](1);
        carryBPs[0] = 2000; // 20% carry

        vm.startPrank(ownerPlatform);

        // Mint official tokens to crowdfunding contract for later distribution
        token.mint(address(crowdfunding), 10000e6);

        uint256 campaignId = crowdfunding.launchCampaign(
            6700e6, // minTarget (2/3 of maxTarget)
            10000e6, // maxTarget
            startTime,
            endTime,
            vestingStart,
            vestingDuration,
            USDC,
            address(token),
            200,
            ownerPlatform,
            ownerCreator,
            creatorVault,
            leaders,
            minContribs,
            carryBPs
        );
        vm.stopPrank();

        // Move to campaign start time
        vm.warp(startTime);

        // Mock fresh price feed data after time warp
        mockPriceFeedData();

        // Setup investor with USDC
        dealToken(USDC, investor, 7000e6); // Increased to meet minTarget

        // Invest in campaign
        vm.startPrank(investor);
        IERC20(USDC).approve(address(crowdfunding), 7000e6);
        crowdfunding.invest(campaignId, 7000e6); // Invest enough to reach minTarget

        // Move to after campaign end
        vm.warp(vestingStart + vestingDuration / 2);

        // Get campaign token address
        Campaign memory campaign = crowdfunding.getCampaign(campaignId);
        address campaignTokenAddr = campaign.campaignToken;

        // Approve campaign token spending
        IERC20(campaignTokenAddr).approve(address(crowdfunding), 7000e6);

        // Swap half of campaign tokens
        crowdfunding.swapForOfficialToken(campaignId, 3500e6);

        // Check received tokens (should be ~50% of 3500e6 due to vesting)
        uint256 officialTokenBalance = token.balanceOf(investor);
        assertGt(officialTokenBalance, 0, "Should have received official tokens");
        assertApproxEqRel(officialTokenBalance, 1750e6, 0.01e18, "Should receive ~50% of tokens due to vesting");
        console.log("Official token balance:", officialTokenBalance);

        vm.stopPrank();
    }

    function test_UnsupportedToken() public {
        vm.startPrank(investor);

        address randomToken = makeAddr("randomToken");

        vm.expectRevert("Unsupported token");
        crowdfunding.getUSDPrice(randomToken);

        vm.expectRevert("Unsupported token");
        crowdfunding.getMaxTargetInToken(randomToken);

        vm.stopPrank();
    }

    function test_AnnualLimitResetAfter365Days() public {
        uint32 startTime = uint32(block.timestamp + 1 days);
        uint32 endTime = startTime + 30 days;
        uint32 vestingStart = endTime;
        uint32 vestingDuration = 180 days;

        // Setup leader arrays
        address[] memory leaders = new address[](1);
        leaders[0] = makeAddr("leader");

        uint256[] memory minContribs = new uint256[](1);
        minContribs[0] = 500e6; // 500 USDC min contribution

        uint256[] memory carryBPs = new uint256[](1);
        carryBPs[0] = 2000; // 20% carry

        vm.startPrank(ownerPlatform);

        // Mint official tokens to crowdfunding contract for later distribution
        token.mint(address(crowdfunding), 20000e6); // Increased to cover both campaigns

        uint256 campaignId1 = crowdfunding.launchCampaign(
            6700e6, // minTarget (exactly 2/3 of maxTarget)
            10000e6, // maxTarget
            startTime,
            endTime,
            vestingStart,
            vestingDuration,
            USDC,
            address(token),
            200,
            ownerPlatform,
            ownerCreator,
            creatorVault,
            leaders,
            minContribs,
            carryBPs
        );
        vm.stopPrank();

        // Move to first campaign start time
        vm.warp(startTime);
        mockPriceFeedData();

        // Setup investor with USDC
        dealToken(USDC, investor, 2000e6);

        // Invest in first campaign
        vm.startPrank(investor);
        IERC20(USDC).approve(address(crowdfunding), 1000e6);
        crowdfunding.invest(campaignId1, 1000e6);

        // Check that the investment was successful
        (uint256 amount, bool claimed, uint256 investTime, uint256 investmentCount) =
            crowdfunding.getInvestment(campaignId1, investor);
        assertApproxEqRel(
            crowdfunding.investedBRLThisYear(investor),
            2000e18, // Expect 2000 BRL (1000 USD * 2 since 1 USD = 2 BRL)
            0.01e18,
            "Investment BRL amount should be recorded"
        );

        // Warp time forward 365 days
        vm.warp(block.timestamp + 365 days);
        vm.stopPrank();

        // Launch second campaign with new timestamps
        vm.startPrank(ownerPlatform);
        uint32 newStartTime = uint32(block.timestamp + 2 days);
        uint32 newEndTime = newStartTime + 30 days;
        uint32 newVestingStart = newEndTime;
        uint32 newVestingDuration = 180 days;

        uint256 campaignId2 = crowdfunding.launchCampaign(
            6700e6,
            10000e6,
            newStartTime,
            newEndTime,
            newVestingStart,
            newVestingDuration,
            USDC,
            address(token),
            200,
            ownerPlatform,
            ownerCreator,
            creatorVault,
            leaders,
            minContribs,
            carryBPs
        );
        vm.stopPrank();

        // Move to second campaign start time and mock fresh price data
        vm.warp(newStartTime);
        mockPriceFeedData();

        // Try to invest in second campaign
        vm.startPrank(investor);
        IERC20(USDC).approve(address(crowdfunding), 1000e6);
        crowdfunding.invest(campaignId2, 1000e6);

        // Check that the investment limit was reset and the new investment was successful
        (amount, claimed, investTime, investmentCount) = crowdfunding.getInvestment(campaignId2, investor);
        assertApproxEqRel(
            crowdfunding.investedBRLThisYear(investor),
            2000e18, // Expect 2000 BRL (1000 USD * 2 since 1 USD = 2 BRL)
            0.01e18,
            "Investment BRL amount should reset after 365 days"
        );

        vm.stopPrank();
    }

    function test_ExtendDeadline() public {
        // Setup campaign
        uint32 startTime = uint32(block.timestamp + 1 days);
        uint32 endTime = startTime + 30 days;
        uint32 vestingStart = endTime;
        uint32 vestingDuration = 180 days;

        // Setup leader arrays
        address[] memory leaders = new address[](1);
        leaders[0] = makeAddr("leader");

        uint256[] memory minContribs = new uint256[](1);
        minContribs[0] = 500e6; // 500 USDC min contribution

        uint256[] memory carryBPs = new uint256[](1);
        carryBPs[0] = 2000; // 20% carry

        vm.startPrank(ownerPlatform);
        // Grant CREATOR_ROLE to ownerCreator
        address[] memory creators = new address[](1);
        creators[0] = ownerCreator;
        crowdfunding.setAllowedCreator(creators);

        token.mint(address(crowdfunding), 10000e6);

        uint256 campaignId = crowdfunding.launchCampaign(
            6700e6, // minTarget (2/3 of maxTarget)
            10000e6, // maxTarget
            startTime,
            endTime,
            vestingStart,
            vestingDuration,
            USDC,
            address(token),
            200,
            ownerPlatform,
            ownerCreator,
            creatorVault,
            leaders,
            minContribs,
            carryBPs
        );
        vm.stopPrank();

        // Try to extend deadline
        vm.startPrank(ownerCreator);
        uint32 newEndTime = endTime + 30 days;
        crowdfunding.extendDeadline(campaignId, newEndTime);

        // Verify the deadline was extended
        Campaign memory campaign = crowdfunding.getCampaign(campaignId);
        assertEq(campaign.endAt, newEndTime, "Deadline should be extended");

        // Try to extend beyond 180 days (should fail)
        uint32 invalidEndTime = startTime + 181 days;
        vm.expectRevert("Exceeds 180 days");
        crowdfunding.extendDeadline(campaignId, invalidEndTime);
        vm.stopPrank();

        // Non-creator should not be able to extend deadline
        vm.startPrank(investor);
        vm.expectRevert("Not campaign creator");
        crowdfunding.extendDeadline(campaignId, newEndTime + 1 days);
        vm.stopPrank();
    }

    function test_DesistFromInvestment() public {
        // Setup campaign
        uint32 startTime = uint32(block.timestamp + 1 days);
        uint32 endTime = startTime + 30 days;
        uint32 vestingStart = endTime;
        uint32 vestingDuration = 180 days;

        // Setup leader arrays
        address[] memory leaders = new address[](1);
        leaders[0] = makeAddr("leader");

        uint256[] memory minContribs = new uint256[](1);
        minContribs[0] = 500e6; // 500 USDC min contribution

        uint256[] memory carryBPs = new uint256[](1);
        carryBPs[0] = 2000; // 20% carry

        vm.startPrank(ownerPlatform);
        token.mint(address(crowdfunding), 10000e6);

        uint256 campaignId = crowdfunding.launchCampaign(
            6700e6, // minTarget (2/3 of maxTarget)
            10000e6, // maxTarget
            startTime,
            endTime,
            vestingStart,
            vestingDuration,
            USDC,
            address(token),
            200,
            ownerPlatform,
            ownerCreator,
            creatorVault,
            leaders,
            minContribs,
            carryBPs
        );
        vm.stopPrank();

        // Move to campaign start time
        vm.warp(startTime);
        mockPriceFeedData();

        // Setup investor with USDC and invest
        dealToken(USDC, investor, 2000e6);
        vm.startPrank(investor);
        IERC20(USDC).approve(address(crowdfunding), 2000e6);

        // Make first investment
        crowdfunding.invest(campaignId, 1000e6);

        // Check initial investment
        (uint256 amount, bool claimed, uint256 investTime, uint256 investmentCount) =
            crowdfunding.getInvestment(campaignId, investor);
        assertEq(amount, 1000e6, "Investment should be recorded");
        assertEq(investmentCount, 1, "Should have one investment");

        // Make second investment
        crowdfunding.invest(campaignId, 500e6);

        // Verify second investment
        (amount, claimed, investTime, investmentCount) = crowdfunding.getInvestment(campaignId, investor);
        assertEq(amount, 1500e6, "Total investment should be updated");
        assertEq(investmentCount, 2, "Should have two investments");

        // Desist from first investment within 5 days
        uint256 balanceBeforeUSDC = IERC20(USDC).balanceOf(investor);
        crowdfunding.desist(campaignId, 1); // Desist from first investment
        uint256 balanceAfterUSDC = IERC20(USDC).balanceOf(investor);

        // Verify refund of first investment
        assertEq(balanceAfterUSDC - balanceBeforeUSDC, 1000e6, "Should receive refund for first investment");

        // Check remaining investment
        (amount, claimed, investTime, investmentCount) = crowdfunding.getInvestment(campaignId, investor);
        assertEq(amount, 500e6, "Should have only second investment remaining");
        assertEq(investmentCount, 2, "Investment count should remain unchanged");

        vm.stopPrank();
    }

    function test_ClaimRefundFailedCampaign() public {
        // Setup campaign
        uint32 startTime = uint32(block.timestamp + 1 days);
        uint32 endTime = startTime + 30 days;
        uint32 vestingStart = endTime;
        uint32 vestingDuration = 180 days;

        // Setup leader arrays
        address[] memory leaders = new address[](1);
        leaders[0] = makeAddr("leader");

        uint256[] memory minContribs = new uint256[](1);
        minContribs[0] = 500e6; // 500 USDC min contribution

        uint256[] memory carryBPs = new uint256[](1);
        carryBPs[0] = 2000; // 20% carry

        vm.startPrank(ownerPlatform);
        token.mint(address(crowdfunding), 10000e6);

        uint256 campaignId = crowdfunding.launchCampaign(
            6700e6, // High min target (2/3 of maxTarget)
            10000e6, // maxTarget
            startTime,
            endTime,
            vestingStart,
            vestingDuration,
            USDC,
            address(token),
            200,
            ownerPlatform,
            ownerCreator,
            creatorVault,
            leaders,
            minContribs,
            carryBPs
        );
        vm.stopPrank();

        // Move to campaign start time
        vm.warp(startTime);
        mockPriceFeedData();

        // Setup investor with USDC and invest
        dealToken(USDC, investor, 2000e6);
        vm.startPrank(investor);
        IERC20(USDC).approve(address(crowdfunding), 1000e6);
        crowdfunding.invest(campaignId, 1000e6);

        // Move past campaign end
        vm.warp(endTime + 1);

        // Claim refund (campaign failed to reach min target)
        uint256 balanceBefore = IERC20(USDC).balanceOf(investor);
        crowdfunding.claimRefund(campaignId);
        uint256 balanceAfter = IERC20(USDC).balanceOf(investor);

        // Verify refund
        assertEq(balanceAfter - balanceBefore, 1000e6, "Should receive full refund");
        vm.stopPrank();
    }

    function test_CreatorClaimSuccessfulCampaign() public {
        // Setup campaign
        uint32 startTime = uint32(block.timestamp + 1 days);
        uint32 endTime = startTime + 30 days;
        uint32 vestingStart = endTime;
        uint32 vestingDuration = 180 days;

        // Setup multiple leaders
        address[] memory investorLeaders = new address[](2);
        investorLeaders[0] = makeAddr("leader1");
        investorLeaders[1] = makeAddr("leader2");

        uint256[] memory leaderMinContribs = new uint256[](2);
        leaderMinContribs[0] = 500e6; // 500 USDC minimum for first leader
        leaderMinContribs[1] = 500e6; // 500 USDC minimum for second leader

        uint256[] memory leaderCarryBPs = new uint256[](2);
        leaderCarryBPs[0] = 1000; // 10% carry for first leader
        leaderCarryBPs[1] = 1000; // 10% carry for second leader

        address creatorWallet = makeAddr("creatorWallet"); // Creator's authorized address

        // Grant roles to all participants
        vm.startPrank(ownerPlatform);
        address[] memory allowedInvestors = new address[](3);
        allowedInvestors[0] = investorLeaders[0];
        allowedInvestors[1] = investorLeaders[1];
        allowedInvestors[2] = investor;
        crowdfunding.setAllowedInvestor(allowedInvestors, true);
        crowdfunding.setAnnualLimit(3400e18);

        // Grant CREATOR_ROLE to creatorWallet
        address[] memory creators = new address[](1);
        creators[0] = creatorWallet;
        crowdfunding.setAllowedCreator(creators);
        vm.stopPrank();

        vm.startPrank(ownerPlatform);
        token.mint(address(crowdfunding), 10000e6);

        uint256 campaignId = crowdfunding.launchCampaign(
            6700e6, // minTarget (2/3 of maxTarget)
            10000e6, // maxTarget
            startTime,
            endTime,
            vestingStart,
            vestingDuration,
            USDC,
            address(token),
            200, // 2% fee
            ownerPlatform, // Platform wallet
            creatorWallet, // Creator's authorized address
            creatorVault, // Vault to receive funds
            investorLeaders,
            leaderMinContribs,
            leaderCarryBPs
        );
        vm.stopPrank();

        // Move to campaign start time
        vm.warp(startTime);
        mockPriceFeedData();

        // First leader invests
        dealToken(USDC, investorLeaders[0], 500e6);
        vm.startPrank(investorLeaders[0]);
        IERC20(USDC).approve(address(crowdfunding), 500e6);
        crowdfunding.invest(campaignId, 500e6);
        vm.stopPrank();

        // Second leader invests
        dealToken(USDC, investorLeaders[1], 500e6);
        vm.startPrank(investorLeaders[1]);
        console.log("Address of investorLeaders[1]:", address(investorLeaders[1]));
        IERC20(USDC).approve(address(crowdfunding), 500e6);
        crowdfunding.invest(campaignId, 500e6);
        vm.stopPrank();

        // Regular investor invests
        dealToken(USDC, investor, 1000e6);
        vm.startPrank(investor);
        IERC20(USDC).approve(address(crowdfunding), 1000e6);
        crowdfunding.invest(campaignId, 1000e6);
        vm.stopPrank();

        // Move past campaign end
        vm.warp(endTime + 1);

        // Creator claims funds
        vm.startPrank(creatorWallet);

        // Track balances
        dealToken(USDC, ownerPlatform, 0);
        dealToken(USDC, creatorVault, 0);
        dealToken(USDC, investorLeaders[0], 0);
        dealToken(USDC, investorLeaders[1], 0);

        uint256 creatorBalanceBefore = IERC20(USDC).balanceOf(creatorVault);
        uint256 platformBalanceBefore = IERC20(USDC).balanceOf(ownerPlatform);
        uint256 leader1BalanceBefore = IERC20(USDC).balanceOf(investorLeaders[0]);
        uint256 leader2BalanceBefore = IERC20(USDC).balanceOf(investorLeaders[1]);

        crowdfunding.claimCreator(campaignId);

        uint256 creatorBalanceAfter = IERC20(USDC).balanceOf(creatorVault);
        uint256 platformBalanceAfter = IERC20(USDC).balanceOf(ownerPlatform);
        uint256 leader1BalanceAfter = IERC20(USDC).balanceOf(investorLeaders[0]);
        uint256 leader2BalanceAfter = IERC20(USDC).balanceOf(investorLeaders[1]);

        // Calculate expected values
        uint256 totalInvested = 2000e6; // 2000 USDC total
        uint256 platformFee = (totalInvested * 200) / 10000; // 2% fee = 40 USDC
        uint256 remainingAfterFee = totalInvested - platformFee; // 1960 USDC
        uint256 leader1Carry = (remainingAfterFee * 1000) / 10000; // 10% carry = 196 USDC
        uint256 leader2Carry = (remainingAfterFee * 1000) / 10000; // 10% carry = 196 USDC
        uint256 totalLeaderCarry = leader1Carry + leader2Carry; // 392 USDC
        uint256 creatorAmount = remainingAfterFee - totalLeaderCarry; // 1568 USDC

        // Log all values for transparency
        console2.log("Total invested:", totalInvested);
        console2.log("Platform fee (2%):", platformFee);
        console2.log("Remaining after fee:", remainingAfterFee);
        console2.log("Leader 1 carry (10%):", leader1Carry);
        console2.log("Leader 2 carry (10%):", leader2Carry);
        console2.log("Total leader carry (20%):", totalLeaderCarry);
        console2.log("Creator should get:", creatorAmount);
        console2.log("Creator actually got:", creatorBalanceAfter - creatorBalanceBefore);
        console2.log("Platform fee received:", platformBalanceAfter - platformBalanceBefore);
        console2.log("Leader 1 carry received:", leader1BalanceAfter - leader1BalanceBefore);
        console2.log("Leader 2 carry received:", leader2BalanceAfter - leader2BalanceBefore);

        // Verify all calculations
        assertEq(platformFee, 40e6, "Platform fee should be 2% of total");
        assertEq(remainingAfterFee, 1960e6, "Remaining after fee should be 98% of total");
        assertEq(leader1Carry, 196e6, "Leader 1 carry should be 10% of remaining");
        assertEq(leader2Carry, 196e6, "Leader 2 carry should be 10% of remaining");
        assertEq(totalLeaderCarry, 392e6, "Total leader carry should be 20% of remaining");
        assertEq(creatorAmount, 1568e6, "Creator amount should be remaining minus total carry");

        // Verify actual transfers
        assertEq(platformBalanceAfter - platformBalanceBefore, platformFee, "Platform should receive fee");
        assertEq(leader1BalanceAfter - leader1BalanceBefore, leader1Carry, "Leader 1 should receive carry");
        assertEq(leader2BalanceAfter - leader2BalanceBefore, leader2Carry, "Leader 2 should receive carry");
        assertEq(
            creatorBalanceAfter - creatorBalanceBefore, creatorAmount, "Creator vault should receive remaining amount"
        );

        // Try to claim again (should fail)
        vm.expectRevert("Already claimed");
        crowdfunding.claimCreator(campaignId);
        vm.stopPrank();
    }

    function test_VestingAndTokenSwap() public {
        // Setup campaign
        uint32 startTime = uint32(block.timestamp + 1 days);
        uint32 endTime = startTime + 30 days;
        uint32 vestingStart = endTime;
        uint32 vestingDuration = 180 days;

        // Setup leader arrays
        address[] memory leaders = new address[](1);
        leaders[0] = makeAddr("leader");

        uint256[] memory minContribs = new uint256[](1);
        minContribs[0] = 500e6; // 500 USDC min contribution

        uint256[] memory carryBPs = new uint256[](1);
        carryBPs[0] = 2000; // 20% carry

        vm.startPrank(ownerPlatform);
        token.mint(address(crowdfunding), 10000e6);

        uint256 campaignId = crowdfunding.launchCampaign(
            6700e6, // minTarget (2/3 of maxTarget)
            10000e6, // maxTarget
            startTime,
            endTime,
            vestingStart,
            vestingDuration,
            USDC,
            address(token),
            200,
            ownerPlatform,
            ownerCreator,
            creatorVault,
            leaders,
            minContribs,
            carryBPs
        );
        vm.stopPrank();

        // Move to campaign start time and invest
        vm.warp(startTime);
        mockPriceFeedData();
        dealToken(USDC, investor, 7000e6); // Increased to meet minTarget

        vm.startPrank(investor);
        IERC20(USDC).approve(address(crowdfunding), 7000e6);
        crowdfunding.invest(campaignId, 7000e6); // Invest enough to reach minTarget

        // Move to middle of vesting period
        vm.warp(vestingStart + vestingDuration / 2);

        Campaign memory campaign = crowdfunding.getCampaign(campaignId);
        IERC20(campaign.campaignToken).approve(address(crowdfunding), 7000e6);

        // Swap half of campaign tokens
        crowdfunding.swapForOfficialToken(campaignId, 3500e6);

        // Check received tokens (should be ~50% of 3500e6 due to vesting)
        uint256 officialTokenBalance = token.balanceOf(investor);
        assertGt(officialTokenBalance, 0, "Should have received official tokens");
        assertApproxEqRel(officialTokenBalance, 1750e6, 0.01e18, "Should receive ~50% of tokens due to vesting");
        console.log("Official token balance:", officialTokenBalance);

        vm.stopPrank();
    }

    function test_EdgeCasesAndValidation() public {
        uint32 startTime = uint32(block.timestamp + 1 days);
        uint32 endTime = startTime + 30 days;
        uint32 vestingStart = endTime;
        uint32 vestingDuration = 180 days;

        // Setup leader arrays
        address[] memory leaders = new address[](1);
        leaders[0] = makeAddr("leader");

        uint256[] memory minContribs = new uint256[](1);
        minContribs[0] = 500e6; // 500 USDC min contribution

        uint256[] memory carryBPs = new uint256[](1);
        carryBPs[0] = 2000; // 20% carry

        vm.startPrank(ownerPlatform);

        // Try to create campaign with invalid dates
        vm.expectRevert("Invalid start time");
        crowdfunding.launchCampaign(
            6700e6,
            10000e6,
            uint32(block.timestamp - 1), // Past start time
            endTime,
            vestingStart,
            vestingDuration,
            USDC,
            address(token),
            200,
            ownerPlatform,
            ownerCreator,
            creatorVault,
            leaders,
            minContribs,
            carryBPs
        );

        // Try to create campaign with invalid targets
        vm.expectRevert("Invalid targets");
        crowdfunding.launchCampaign(
            0, // Invalid min target
            10000e6,
            startTime,
            endTime,
            vestingStart,
            vestingDuration,
            USDC,
            address(token),
            200,
            ownerPlatform,
            ownerCreator,
            creatorVault,
            leaders,
            minContribs,
            carryBPs
        );

        // Try to create campaign with minTarget less than 2/3 of maxTarget
        vm.expectRevert("minTarget < 2/3 of maxTarget");
        crowdfunding.launchCampaign(
            6000e6, // 6M (less than 2/3 of 10M)
            10000e6, // 10M
            startTime,
            endTime,
            vestingStart,
            vestingDuration,
            USDC,
            address(token),
            200,
            ownerPlatform,
            ownerCreator,
            creatorVault,
            leaders,
            minContribs,
            carryBPs
        );

        // Try to create campaign with too high platform fee
        vm.expectRevert("Fee too high (max 10%)");
        crowdfunding.launchCampaign(
            1000e6,
            1000e6, // Same as minTarget to pass 2/3 requirement
            startTime,
            endTime,
            vestingStart,
            vestingDuration,
            USDC,
            address(token),
            1100, // 11% fee
            ownerPlatform,
            ownerCreator,
            creatorVault,
            leaders,
            minContribs,
            carryBPs
        );

        // Create a valid campaign (with minTarget exactly 2/3 of maxTarget)
        uint256 maxTarget = 9000e6;
        uint256 minTarget = 6000e6; // Exactly 2/3 of maxTarget
        uint256 campaignId = crowdfunding.launchCampaign(
            minTarget,
            maxTarget,
            startTime,
            endTime,
            vestingStart,
            vestingDuration,
            USDC,
            address(token),
            200,
            ownerPlatform,
            ownerCreator,
            creatorVault,
            leaders,
            minContribs,
            carryBPs
        );

        // Try to create another campaign before cooldown period
        vm.expectRevert("Creator in cooldown period");
        crowdfunding.launchCampaign(
            minTarget,
            maxTarget,
            startTime + 1 days,
            endTime + 1 days,
            vestingStart + 1 days,
            vestingDuration,
            USDC,
            address(token),
            200,
            ownerPlatform,
            ownerCreator,
            creatorVault,
            leaders,
            minContribs,
            carryBPs
        );

        vm.stopPrank();

        // Move to campaign start time
        vm.warp(startTime);
        mockPriceFeedData();

        // Try to invest with unauthorized user
        address randomUser = makeAddr("random");
        dealToken(USDC, randomUser, 2000e6);

        vm.startPrank(randomUser);
        IERC20(USDC).approve(address(crowdfunding), 1000e6);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, randomUser, keccak256("INVESTOR_ROLE")
            )
        );
        crowdfunding.invest(campaignId, 1000e6);
        vm.stopPrank();
    }

    function test_ETHPriceFeed() public {
        vm.startPrank(investor);

        // Mock ETH/USD price feed data
        vm.mockCall(
            ETH_PRICE_FEED,
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(
                uint80(1),
                int256(2000e8), // $2000 with 8 decimals
                block.timestamp,
                block.timestamp,
                uint80(1)
            )
        );

        // Get ETH price
        uint256 ethPrice = crowdfunding.getUSDPrice(address(0));
        console.log("ETH/USD Price:", ethPrice / 1e8); // Display in USD

        // Price should be around $2000
        assertApproxEqRel(ethPrice, 2000e8, 0.1e18, "ETH price should be close to $2000");

        // Test stale price
        vm.warp(block.timestamp + 25 hours);
        vm.expectRevert(Crowdfunding.StalePrice.selector);
        crowdfunding.getUSDPrice(address(0));

        vm.stopPrank();
    }

    function test_RealPriceFeeds() public {
        // Select the mainnet fork to ensure we have access to real price feeds
        vm.selectFork(mainnetFork);

        // Test USDC price feed
        uint256 usdcPrice = crowdfunding.getUSDPrice(USDC);
        console.log("Real USDC/USD Price:", usdcPrice);
        // USDC should be very close to $1 (with 8 decimals)
        assertApproxEqRel(usdcPrice, 1e8, 0.01e18, "USDC price too far from $1");

        // Test USDT price feed
        uint256 usdtPrice = crowdfunding.getUSDPrice(USDT);
        console.log("Real USDT/USD Price:", usdtPrice);
        // USDT should be very close to $1 (with 8 decimals)
        assertApproxEqRel(usdtPrice, 1e8, 0.01e18, "USDT price too far from $1");

        // Test ETH price feed
        uint256 ethPrice = crowdfunding.getUSDPrice(address(0));
        console.log("Real ETH/USD Price:", ethPrice / 1e8, "USD");
        // ETH price should be > 0 and reasonable (e.g., > $100)
        assertGt(ethPrice, 100e8, "ETH price seems too low");
        assertLt(ethPrice, 100000e8, "ETH price seems too high");

        // Test BRL conversion
        uint256 usdAmount = 1000e18; // $1000 with 18 decimals
        uint256 brlAmount = crowdfunding.getBRLPrice(usdAmount);
        console.log("$1000 in BRL:", brlAmount / 1e18, "BRL");
        // BRL amount should be higher than USD amount (as 1 USD > 1 BRL)
        assertGt(brlAmount, usdAmount, "BRL should be worth less than USD");

        // Test max target in USDC
        uint256 maxUSDCTarget = crowdfunding.getMaxTargetInToken(USDC);
        console.log("Max campaign target in USDC:", maxUSDCTarget / 1e6, "USDC");
        // Should be reasonable amount based on 15M BRL limit
        assertGt(maxUSDCTarget, 1000000e6, "Max USDC target seems too low");
        assertLt(maxUSDCTarget, 100000000e6, "Max USDC target seems too high");
    }

    function test_ETHInvestmentWithLeader() public {
        uint32 startTime = uint32(block.timestamp + 1 days);
        uint32 endTime = startTime + 30 days;
        uint32 vestingStart = endTime;
        uint32 vestingDuration = 180 days;

        // Setup multiple leaders
        address[] memory investorLeaders = new address[](2);
        investorLeaders[0] = makeAddr("leader1");
        investorLeaders[1] = makeAddr("leader2");

        uint256[] memory leaderMinContribs = new uint256[](2);
        leaderMinContribs[0] = 0.25 ether; // 0.25 ETH minimum for first leader
        leaderMinContribs[1] = 0.25 ether; // 0.25 ETH minimum for second leader

        uint256[] memory leaderCarryBPs = new uint256[](2);
        leaderCarryBPs[0] = 1000; // 10% carry for first leader
        leaderCarryBPs[1] = 1000; // 10% carry for second leader

        address creatorWallet = makeAddr("creatorWallet"); // Creator's authorized address

        vm.startPrank(ownerPlatform);
        // Allow leaders and investor to invest
        address[] memory allowedInvestors = new address[](3);
        allowedInvestors[0] = investorLeaders[0];
        allowedInvestors[1] = investorLeaders[1];
        allowedInvestors[2] = investor;
        crowdfunding.setAllowedInvestor(allowedInvestors, true);
        crowdfunding.setAnnualLimit(3400e18);

        // Grant CREATOR_ROLE to creatorWallet
        address[] memory creators = new address[](1);
        creators[0] = creatorWallet;
        crowdfunding.setAllowedCreator(creators);
        vm.stopPrank();

        vm.startPrank(ownerPlatform);
        // Create campaign with ETH as payment token
        uint256 campaignId = crowdfunding.launchCampaign(
            1.14 ether, // minTarget (exactly 2/3 of maxTarget)
            1.7 ether, // maxTarget
            startTime,
            endTime,
            vestingStart,
            vestingDuration,
            address(0), // ETH as payment token
            address(token),
            200, // 2% platform fee
            ownerPlatform, // Platform wallet
            creatorWallet, // Creator's authorized address
            creatorVault, // Vault to receive funds
            investorLeaders,
            leaderMinContribs,
            leaderCarryBPs
        );

        token.mint(address(crowdfunding), 2 ether); // Mint tokens for distribution
        vm.stopPrank();

        // Move to campaign start
        vm.warp(startTime);
        mockPriceFeedData();

        // First leader invests
        vm.deal(investorLeaders[0], 0.25 ether);
        vm.startPrank(investorLeaders[0]);
        crowdfunding.invest{value: 0.25 ether}(campaignId, 0.25 ether);
        vm.stopPrank();

        // Second leader invests
        vm.deal(investorLeaders[1], 0.25 ether);
        vm.startPrank(investorLeaders[1]);
        crowdfunding.invest{value: 0.25 ether}(campaignId, 0.25 ether);
        vm.stopPrank();

        // Regular investor invests
        vm.deal(investor, 0.5 ether);
        vm.startPrank(investor);
        crowdfunding.invest{value: 0.5 ether}(campaignId, 0.5 ether);
        vm.stopPrank();

        // Move to end of campaign
        vm.warp(endTime + 1);

        // Creator claims funds
        vm.startPrank(creatorWallet);
        uint256 creatorBalanceBefore = creatorVault.balance;
        uint256 platformBalanceBefore = ownerPlatform.balance;
        uint256 leader1BalanceBefore = investorLeaders[0].balance;
        uint256 leader2BalanceBefore = investorLeaders[1].balance;

        crowdfunding.claimCreator(campaignId);

        uint256 creatorBalanceAfter = creatorVault.balance;
        uint256 platformBalanceAfter = ownerPlatform.balance;
        uint256 leader1BalanceAfter = investorLeaders[0].balance;
        uint256 leader2BalanceAfter = investorLeaders[1].balance;

        // Calculate expected values
        uint256 totalInvested = 1 ether;
        uint256 platformFee = (totalInvested * 200) / 10000; // 2% fee
        uint256 remainingAfterFee = totalInvested - platformFee;
        uint256 leader1Carry = (remainingAfterFee * 1000) / 10000; // 10% carry
        uint256 leader2Carry = (remainingAfterFee * 1000) / 10000; // 10% carry
        uint256 totalLeaderCarry = leader1Carry + leader2Carry;
        uint256 creatorAmount = remainingAfterFee - totalLeaderCarry;

        // Log all values for transparency
        console2.log("Total invested:", totalInvested);
        console2.log("Platform fee (2%):", platformFee);
        console2.log("Remaining after fee:", remainingAfterFee);
        console2.log("Leader 1 carry (10%):", leader1Carry);
        console2.log("Leader 2 carry (10%):", leader2Carry);
        console2.log("Total leader carry (20%):", totalLeaderCarry);
        console2.log("Creator should get:", creatorAmount);
        console2.log("Creator actually got:", creatorBalanceAfter - creatorBalanceBefore);
        console2.log("Platform fee received:", platformBalanceAfter - platformBalanceBefore);
        console2.log("Leader 1 carry received:", leader1BalanceAfter - leader1BalanceBefore);
        console2.log("Leader 2 carry received:", leader2BalanceAfter - leader2BalanceBefore);

        // Verify all calculations
        assertEq(platformFee, 0.02 ether, "Platform fee should be 2% of total");
        assertEq(remainingAfterFee, 0.98 ether, "Remaining after fee should be 98% of total");
        assertEq(leader1Carry, 0.098 ether, "Leader 1 carry should be 10% of remaining");
        assertEq(leader2Carry, 0.098 ether, "Leader 2 carry should be 10% of remaining");
        assertEq(totalLeaderCarry, 0.196 ether, "Total leader carry should be 20% of remaining");
        assertEq(creatorAmount, 0.784 ether, "Creator amount should be remaining minus total carry");

        // Verify actual transfers
        assertEq(platformBalanceAfter - platformBalanceBefore, platformFee, "Platform should receive fee");
        assertEq(leader1BalanceAfter - leader1BalanceBefore, leader1Carry, "Leader 1 should receive carry");
        assertEq(leader2BalanceAfter - leader2BalanceBefore, leader2Carry, "Leader 2 should receive carry");
        assertEq(
            creatorBalanceAfter - creatorBalanceBefore, creatorAmount, "Creator vault should receive remaining amount"
        );

        vm.stopPrank();
    }

    function test_ETHDesistAndRefund() public {
        uint32 startTime = uint32(block.timestamp + 1 days);
        uint32 endTime = startTime + 30 days;
        uint32 vestingStart = endTime;
        uint32 vestingDuration = 180 days;

        // Setup empty leader arrays for no-leader campaign
        address[] memory noLeaders = new address[](0);
        uint256[] memory noMinContribs = new uint256[](0);
        uint256[] memory noCarryBPs = new uint256[](0);

        vm.startPrank(ownerPlatform);
        uint256 campaignId = crowdfunding.launchCampaign(
            6.7 ether, // minTarget (2/3 of maxTarget)
            10 ether, // maxTarget
            startTime,
            endTime,
            vestingStart,
            vestingDuration,
            address(0), // ETH as payment token
            address(token),
            200,
            platformWallet,
            ownerCreator,
            creatorVault,
            noLeaders,
            noMinContribs,
            noCarryBPs
        );
        vm.stopPrank();

        // Move to campaign start
        vm.warp(startTime);
        mockPriceFeedData();

        // Test desist functionality
        vm.deal(investor, 1 ether);
        vm.startPrank(investor);

        // First investment - will be desisted
        crowdfunding.invest{value: 0.5 ether}(campaignId, 0.5 ether);
        uint256 balanceBefore = investor.balance;
        crowdfunding.desist(campaignId, 1); // Use investment ID 1
        uint256 balanceAfter = investor.balance;
        assertEq(balanceAfter - balanceBefore, 0.5 ether, "Should receive full ETH refund from desist");

        // Move forward 120 days for the cooldown period
        vm.warp(block.timestamp + 130 days);
        vm.stopPrank();

        // Calculate new timestamps for second campaign
        uint32 newStartTime = uint32(block.timestamp + 130 days);
        uint32 newEndTime = newStartTime + 30 days;
        uint32 newVestingStart = newEndTime;

        vm.startPrank(ownerPlatform);
        uint256 campaignId2 = crowdfunding.launchCampaign(
            6.7 ether,
            10 ether,
            newStartTime,
            newEndTime,
            newVestingStart,
            180 days,
            address(0), // ETH as payment token
            address(token),
            200,
            ownerCreator,
            ownerCreator,
            creatorVault,
            new address[](0),
            new uint256[](0),
            new uint256[](0)
        );
        vm.stopPrank();

        // Move to the start of the second campaign
        vm.warp(newStartTime);
        mockPriceFeedData();

        // Test refund functionality with new campaign
        vm.startPrank(investor);
        crowdfunding.invest{value: 0.25 ether}(campaignId2, 0.25 ether);
        vm.stopPrank();

        // Move past campaign end
        vm.warp(newEndTime + 1);

        // Claim refund (campaign failed to reach min target)
        vm.startPrank(investor);
        balanceBefore = investor.balance;
        crowdfunding.claimRefund(campaignId2);
        balanceAfter = investor.balance;
        assertEq(balanceAfter - balanceBefore, 0.25 ether, "Should receive ETH refund for failed campaign");
        vm.stopPrank();
    }

    // Helper function to deal USDC/USDT to addresses
    function dealToken(address tokenAddr, address to, uint256 amount) internal {
        stdstoreCrowdfunding.target(tokenAddr).sig(IERC20(tokenAddr).balanceOf.selector).with_key(to).checked_write(
            amount
        );
    }

    function mockPriceFeedData() internal {
        // Mock USDC/USD price feed
        vm.mockCall(
            0x7e860098F58bBFC8648a4311b374B1D669a2bc6B, // USDC/USD price feed on Base
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(
                uint80(1), // roundId
                int256(1e8), // price ($1 with 8 decimals)
                block.timestamp, // startedAt
                block.timestamp, // updatedAt
                uint80(1) // answeredInRound
            )
        );

        // Mock USDT/USD price feed
        vm.mockCall(
            0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9, // USDT/USD price feed on Base
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(uint80(1), int256(1e8), block.timestamp, block.timestamp, uint80(1))
        );

        // Mock BRL/USD price feed
        vm.mockCall(
            0x0b0E64c05083FdF9ED7C5D3d8262c4216eFc9394, // BRL/USD price feed on Base
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(
                uint80(1),
                int256(0.5e8), // ~5 BRL per USD (0.5 USD per BRL)
                block.timestamp,
                block.timestamp,
                uint80(1)
            )
        );

        // Add ETH/USD price feed mock
        vm.mockCall(
            ETH_PRICE_FEED,
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(
                uint80(1),
                int256(2000e8), // $2000 with 8 decimals
                block.timestamp,
                block.timestamp,
                uint80(1)
            )
        );
    }
}
