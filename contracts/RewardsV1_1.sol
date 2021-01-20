// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract RewardsV1_1 is Ownable, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Contract constants
    uint256 public constant DURATION_LOCK = 30 days;
    uint256 public constant DURATION_UNLOCK = 30 days;
    uint256 public constant REWARD_RATE_LOCK = 9700; // 3.00%
    uint256 public constant REWARD_RATE_UNLOCK = 9990; // 0.10%
    uint256 public constant REWARD_RATE_BASE = 10000; // 100%
    uint256 public constant REWARD_PERIOD = 30 days;

    /**
     * BRLC token address
     */
    IERC20 public brlc = IERC20(0x6c4779C1Ae7f953170046Ed265C3Fa34fACFa682);

    event DepositReplenished(
        address indexed user,
        uint256 amount,
        uint256 earnings
    );

    event DepositWithdrawn(
        address indexed user,
        uint256 amount,
        uint256 earnings
    );

    event DepositTransfered(
        address indexed from,
        address indexed to,
        uint256 balance,
        uint256 replenishDate
    );

    event DepositChanged(
        address indexed user,
        uint256 balance,
        uint256 replenishDate,
        uint256 oldBalance,
        uint256 oldreplenishDate
    );

    /**
     * @dev User deposit state
     */
    enum LockState {Locked, Unlocked}

    /**
     * @dev User deposit account
     */
    struct DepositAccount {
        bool exists;
        uint256 balance;
        uint256 replenishDate;
    }

    /**
     * @dev Deposit account per user
     */
    mapping(address => DepositAccount) private _deposits;

    /**
     * @dev Contract total balance
     */
    uint256 private _totalBalance;

    // *** Modifiers ***

    modifier hasDeposit(address user, LockState state) {
        DepositAccount memory userDeposit = _deposits[user];
        require(userDeposit.exists, "Deposit account doesn't exist");
        (, , LockState depositState) = lockUnlockDetails(
            userDeposit.replenishDate,
            now
        );
        require(depositState == state, "Deposit is in a locked state");
        _;
    }

    // *** Transactions ***

    /**
     * @dev 'deposit'
     */
    function deposit(uint256 amount) external whenNotPaused {
        _deposit(msg.sender, amount);
    }

    /**
     * @dev 'withdraw'
     */
    function withdraw(uint256 amount)
        external
        hasDeposit(msg.sender, LockState.Unlocked)
        whenNotPaused
    {
        _withdraw(msg.sender, amount, false);
    }

    /**
     * @dev 'withdrawAll'
     */
    function withdrawAll()
        external
        hasDeposit(msg.sender, LockState.Unlocked)
        whenNotPaused
    {
        _withdraw(msg.sender, _deposits[msg.sender].balance, false);
    }

    /**
     * @dev 'exitAll'
     */
    function exitAll()
        external
        hasDeposit(msg.sender, LockState.Unlocked)
        whenNotPaused
    {
        _withdraw(msg.sender, _deposits[msg.sender].balance, true);
    }

    /**
     * @dev 'transfer'
     */
    function transfer(address to) external whenNotPaused {
        _transfer(msg.sender, to);
    }

    /**
     * @dev '_transfer'
     */
    function _transfer(address from, address to) internal {
        require(from != to, "formm == to");

        DepositAccount memory fromDeposit = _deposits[from];
        require(fromDeposit.exists, "Deposit account doesn't exist: from");
        require(fromDeposit.balance > 0, "Deposit balance is equal to 0: from");

        DepositAccount memory toDeposit = _deposits[to];
        require(!toDeposit.exists, "Deposit account already exists: to");

        _setDepositAccount(from, 0, now);
        _setDepositAccount(to, fromDeposit.balance, fromDeposit.replenishDate);

        emit DepositTransfered(
            from,
            to,
            fromDeposit.balance,
            fromDeposit.replenishDate
        );
    }

    /**
     * @dev '_deposit'
     */
    function _deposit(address user, uint256 amount) internal {
        require(amount > 0, "Deposit amount must be greater than 0");

        brlc.safeTransferFrom(user, address(this), amount);
        DepositAccount memory userDeposit = _deposits[user];
        uint256 earnings = totalEarnings(
            userDeposit.balance,
            userDeposit.replenishDate,
            now
        );
        _setDepositAccount(
            user,
            userDeposit.balance.add(amount).add(earnings),
            now
        );
        _increaseTotalBalance(amount.add(earnings));

        emit DepositReplenished(user, amount, earnings);
    }

    /**
     * @dev '_withdraw'
     */
    function _withdraw(
        address user,
        uint256 amount,
        bool exit
    ) internal {
        DepositAccount memory userDeposit = _deposits[user];

        require(userDeposit.balance > 0, "Deposit balance is equal to 0");
        require(
            userDeposit.balance >= amount,
            "Withdraw amount can't be greater than deposit balance"
        );

        uint256 earnings = !exit
            ? totalEarnings(userDeposit.balance, userDeposit.replenishDate, now)
            : 0;

        _setDepositAccount(user, userDeposit.balance.sub(amount), now);
        _decreaseTotalBalance(amount);
        brlc.safeTransfer(user, amount.add(earnings));

        emit DepositWithdrawn(user, amount, earnings);
    }

    /**
     * @dev '_increaseTotalBalance'
     */
    function _increaseTotalBalance(uint256 amount) internal {
        _totalBalance = _totalBalance.add(amount);
    }

    /**
     * @dev '_decreaseTotalBalance'
     */
    function _decreaseTotalBalance(uint256 amount) internal {
        _totalBalance = _totalBalance.sub(amount);
    }

    /**
     * @dev '_setDepositAccount'
     */
    function _setDepositAccount(
        address user,
        uint256 balance,
        uint256 replenishDate
    ) internal {
        uint256 oldBalance = _deposits[user].balance;
        uint256 oldReplenishDate = _deposits[user].replenishDate;

        _deposits[user].balance = balance;
        _deposits[user].replenishDate = replenishDate;

        if (!_deposits[user].exists) {
            _deposits[user].exists = true;
        }

        emit DepositChanged(
            user,
            balance,
            replenishDate,
            oldBalance,
            oldReplenishDate
        );
    }

    // *** Earnings ***

    /**
     * @dev 'totalEarnings'
     */
    function totalEarnings(
        uint256 amount,
        uint256 replenishDate,
        uint256 withdrawDate
    ) public pure returns (uint256) {
        (uint256 lockEarnings, uint256 unlockEarnings) = partialEarnings(
            amount,
            replenishDate,
            withdrawDate
        );
        return lockEarnings.add(unlockEarnings);
    }

    /**
     * @dev 'partialEarnings'
     */
    function partialEarnings(
        uint256 amount,
        uint256 replenishDate,
        uint256 withdrawDate
    ) public pure returns (uint256 lockEarnings, uint256 unlockEarnings) {
        uint256 period = DURATION_LOCK.add(DURATION_UNLOCK);
        uint256 duration = withdrawDate.sub(replenishDate);
        uint256 remainder = duration.mod(period);
        uint256 quotient = duration.div(period);

        uint256 lockDuration = DURATION_LOCK.mul(quotient).add(
            remainder > DURATION_LOCK ? DURATION_LOCK : remainder
        );
        lockEarnings = calculateEarnings(
            amount,
            lockDuration,
            REWARD_PERIOD,
            REWARD_RATE_LOCK,
            REWARD_RATE_BASE
        );

        uint256 unlockDuration = DURATION_UNLOCK.mul(quotient).add(
            remainder > DURATION_LOCK ? remainder.sub(DURATION_LOCK) : 0
        );
        unlockEarnings = calculateEarnings(
            amount,
            unlockDuration,
            REWARD_PERIOD,
            REWARD_RATE_UNLOCK,
            REWARD_RATE_BASE
        );
    }

    /**
     * @dev 'calculateEarnings'
     */
    function calculateEarnings(
        uint256 amount,
        uint256 duration,
        uint256 rewardPeriod,
        uint256 rewardRatePtg,
        uint256 rewardRateBase
    ) public pure returns (uint256) {
        if (amount == 0 || duration == 0) return 0;
        uint256 value = amount.mul(duration).div(rewardPeriod);
        return
            value.mul(rewardRateBase).sub(value.mul(rewardRatePtg)).div(
                rewardRateBase
            );
    }

    // *** Lock/Unlock Details ***

    /**
     * @dev 'lockUnlockDetails'
     */
    function lockUnlockDetails(uint256 replenishDate, uint256 withdrawDate)
        public
        pure
        returns (
            uint256 nextLock,
            uint256 nextUnlock,
            LockState state
        )
    {
        uint256 period = DURATION_LOCK.add(DURATION_UNLOCK);
        uint256 duration = withdrawDate.sub(replenishDate);
        uint256 remainder = duration.mod(period);
        uint256 quotient = duration.div(period);

        nextLock = replenishDate.add(quotient.mul(period)).add(period);
        nextUnlock = remainder > DURATION_LOCK
            ? nextLock.add(DURATION_LOCK)
            : nextLock.sub(DURATION_UNLOCK);

        state = nextLock > nextUnlock ? LockState.Locked : LockState.Unlocked;
    }

    // *** Deposit Details ***

    /**
     * @dev 'depositDetails'
     */
    function depositDetails()
        public
        view
        returns (
            bool exists,
            uint256 balance,
            uint256 lockEarnings,
            uint256 unlockEarnings,
            uint256 replenishDate,
            uint256 nextUnlock,
            uint256 nextLock,
            LockState state
        )
    {
        (
            exists,
            balance,
            lockEarnings,
            unlockEarnings,
            replenishDate,
            nextUnlock,
            nextLock,
            state
        ) = depositDetails(msg.sender);
    }

    /**
     * @dev 'depositDetails'
     */
    function depositDetails(address user)
        public
        view
        returns (
            bool exists,
            uint256 balance,
            uint256 lockEarnings,
            uint256 unlockEarnings,
            uint256 replenishDate,
            uint256 nextUnlock,
            uint256 nextLock,
            LockState state
        )
    {
        (
            exists,
            balance,
            lockEarnings,
            unlockEarnings,
            replenishDate,
            nextUnlock,
            nextLock,
            state
        ) = depositDetails(user, now);
    }

    /**
     * @dev 'depositDetails'
     */
    function depositDetails(address user, uint256 withdrawDate)
        public
        view
        returns (
            bool exists,
            uint256 balance,
            uint256 lockEarnings,
            uint256 unlockEarnings,
            uint256 replenishDate,
            uint256 nextUnlock,
            uint256 nextLock,
            LockState state
        )
    {
        DepositAccount memory userDeposit = _deposits[user];
        if (userDeposit.exists) {
            replenishDate = userDeposit.replenishDate;
            balance = userDeposit.balance;
            exists = userDeposit.exists;

            (lockEarnings, unlockEarnings) = partialEarnings(
                userDeposit.balance,
                userDeposit.replenishDate,
                withdrawDate
            );

            (nextLock, nextUnlock, state) = lockUnlockDetails(
                userDeposit.replenishDate,
                withdrawDate
            );
        }
    }    

    /**
     * @dev 'totalBalance'
     */
    function totalBalance() public view returns (uint256) {
        return _totalBalance;
    }

    // *** Pausable ***

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
}
