// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract RewardsV1_0 is Ownable, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event Deposit(
        address indexed user,
        uint256 amount,
        uint256 earnings,
        uint256 unlockDate
    );
    event Withdraw(address indexed user, uint256 amount, uint256 earnings);

    // Contract constants
    uint256 public constant LOCK_DURATION = 30 days;
    uint256 public constant REWARD_PERIOD = 30 days;
    uint256 public constant REWARD_RATE_LOCKED = 9700; // 3.00%
    uint256 public constant REWARD_RATE_UNLOCKED = 9990; // 0.10%
    uint256 public constant REWARD_RATE_BASE = 10000; // 100%
    uint256 private _totalBalance;

    /**
     * BRLC token address
     */
    IERC20 public brlc = IERC20(0x6c4779C1Ae7f953170046Ed265C3Fa34fACFa682);

    /**
     * @dev Represents a user deposut state.
     */
    struct DepositState {
        uint256 balance;
        uint256 unlockDate;
    }

    /**
     * @dev Aggregated deposit state per user.
     */

    mapping(address => DepositState) private _deposits;

    /**
     * @dev 'deposit'
     */
    function deposit(uint256 amount) public whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        DepositState memory depositState = _deposits[msg.sender];
        (uint256 lockEarnings, uint256 unlockEarnings) = calculateEarnings(
            depositState.balance,
            depositState.unlockDate
        );
        depositCore(msg.sender, amount, lockEarnings.add(unlockEarnings));
    }

    /**
     * @dev 'withdrawAll'
     */
    function withdrawAll() public {
        DepositState memory depositState = _deposits[msg.sender];
        require(
            depositState.balance > 0,
            "Deposit balance must be greater than 0"
        );
        require(
            depositState.unlockDate <= now,
            "Deposit must be in the unlocked state"
        );
        (uint256 lockEarnings, uint256 unlockEarnings) = calculateEarnings(
            depositState.balance,
            depositState.unlockDate
        );
        withdrawCore(
            msg.sender,
            depositState.balance,
            lockEarnings.add(unlockEarnings)
        );
    }

    /**
     * @dev 'withdrawCore'
     */

    function withdrawCore(
        address user,
        uint256 amount,
        uint256 earnings
    ) private {
        DepositState storage depositState = _deposits[user];
        depositState.balance = depositState.balance.sub(amount);
        _totalBalance = _totalBalance.sub(amount);
        brlc.safeTransfer(user, amount.add(earnings));
        emit Withdraw(user, amount, earnings);
    }

    /**
     * @dev 'depositCore'
     */
    function depositCore(
        address user,
        uint256 amount,
        uint256 earnings
    ) private {
        brlc.safeTransferFrom(user, address(this), amount);
        DepositState storage depositState = _deposits[user];
        depositState.balance = depositState.balance.add(amount).add(earnings);
        depositState.unlockDate = now.add(LOCK_DURATION);
        _totalBalance = _totalBalance.add(amount).add(earnings);
        emit Deposit(user, amount, earnings, now.add(LOCK_DURATION));
    }

    /**
     * @dev 'calculateEarnings'
     */
    function calculateEarnings(uint256 amount, uint256 unlockDate)
        public
        view
        returns (uint256, uint256)
    {
        uint256 lockDuration = now >= unlockDate
            ? LOCK_DURATION
            : LOCK_DURATION.sub(unlockDate.sub(now));
        uint256 lockEarnings = calculateEarningsCore(
            amount,
            lockDuration,
            REWARD_PERIOD,
            REWARD_RATE_LOCKED,
            REWARD_RATE_BASE
        );
        uint256 unlockDuration = now > unlockDate ? now.sub(unlockDate) : 0;
        uint256 unlockEarnings = unlockDuration > 0
            ? calculateEarningsCore(
                amount,
                unlockDuration,
                REWARD_PERIOD,
                REWARD_RATE_UNLOCKED,
                REWARD_RATE_BASE
            )
            : 0;
        return (lockEarnings, unlockEarnings);
    }

    /**
     * @dev 'calculateEarningsCore'
     */
    function calculateEarningsCore(
        uint256 amount,
        uint256 duration,
        uint256 rewardPeriod,
        uint256 rewardRatePtg,
        uint256 rewardRateBase
    ) public pure returns (uint256) {
        uint256 value = amount.mul(duration).div(rewardPeriod);
        return
            value.mul(rewardRateBase).sub(value.mul(rewardRatePtg)).div(
                rewardRateBase
            );
    }

    /**
     * @dev 'totalBalance'
     */
    function totalBalance() public view returns (uint256) {
        return _totalBalance;
    }

    /**
     * @dev 'depositDetails'
     */
    function depositDetails(address user)
        public
        view
        returns (
            uint256 balance,
            uint256 lockEarnings,
            uint256 unlockEarnings,
            uint256 unlockDate
        )
    {
        DepositState storage depositState = _deposits[user];
        balance = depositState.balance;
        unlockDate = depositState.unlockDate;
        (lockEarnings, unlockEarnings) = calculateEarnings(
            depositState.balance,
            depositState.unlockDate
        );
    }

    /**
     * @dev (Pausable) Triggers stopped state.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev (Pausable) Returns to normal state.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Debugging test function.
     */
    function test_depositDetails(address user)
        public
        view
        returns (
            uint256 amount,
            uint256 lockDuration,
            uint256 lockEarnings,
            uint256 unlockDuration,
            uint256 unlockEarnings,
            uint256 unlockDate,
            uint256 time,
            bool unlocked
        )
    {
        DepositState storage depositState = _deposits[user];
        amount = depositState.balance;
        unlockDate = depositState.unlockDate;

        lockDuration = now >= unlockDate
            ? LOCK_DURATION
            : LOCK_DURATION.sub(unlockDate.sub(now));
        lockEarnings = calculateEarningsCore(
            amount,
            lockDuration,
            REWARD_PERIOD,
            REWARD_RATE_LOCKED,
            REWARD_RATE_BASE
        );

        unlockDuration = now > unlockDate ? now.sub(unlockDate) : 0;
        unlockEarnings = unlockDuration > 0
            ? calculateEarningsCore(
                amount,
                unlockDuration,
                REWARD_PERIOD,
                REWARD_RATE_UNLOCKED,
                REWARD_RATE_BASE
            )
            : 0;

        return (
            amount,
            lockDuration,
            lockEarnings,
            unlockDuration,
            unlockEarnings,
            unlockDate,
            now,
            now >= unlockDate
        );
    }
}
