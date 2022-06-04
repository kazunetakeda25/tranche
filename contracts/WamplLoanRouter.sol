pragma solidity ^0.8.3;

import "./interfaces/ILoanRouter.sol";
import "./interfaces/IBondController.sol";
import "./interfaces/ITranche.sol";
import "./interfaces/IButtonWrapper.sol";
import "./interfaces/IWAMPL.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IWamplLoanRouter.sol";
import "./test/WAMPL.sol";

/**
 * @dev Wampl Loan Router built on top of a LoanRouter of your choosing
 * to allow loans to be created with raw ampl instead of WAMPL
 */
contract WamplLoanRouter is IWamplLoanRouter {
    ILoanRouter public immutable loanRouter;
    IWAMPL public immutable wampl;

    /**
     * @dev Constructor for setting underlying loanRouter and wampl contracts
     * @param _loanRouter The underlying loanRouter that does all the wrapping and trading
     * @param _wampl The WAMPL contract to wrap AMPL in
     */
    constructor(ILoanRouter _loanRouter, IWAMPL _wampl) {
        loanRouter = _loanRouter;
        wampl = _wampl;
    }

    /**
     * @inheritdoc IWamplLoanRouter
     */
    function wrapAndBorrow(
        uint256 underlyingAmount,
        IBondController bond,
        IERC20 currency,
        uint256[] memory sales,
        uint256 minOutput
    ) external override returns (uint256 amountOut) {
        uint256 wamplBalance = _wamplWrap(underlyingAmount, bond);
        uint256 loanAmountOut = loanRouter.wrapAndBorrow(wamplBalance, bond, currency, sales, minOutput);
        _distributeLoanOutput(loanAmountOut, bond, currency);
        return loanAmountOut;
    }

    /**
     * @inheritdoc IWamplLoanRouter
     */
    function wrapAndBorrowMax(
        uint256 underlyingAmount,
        IBondController bond,
        IERC20 currency,
        uint256 minOutput
    ) external override returns (uint256 amountOut) {
        uint256 wamplBalance = _wamplWrap(underlyingAmount, bond);
        uint256 loanAmountOut = loanRouter.wrapAndBorrowMax(wamplBalance, bond, currency, minOutput);
        _distributeLoanOutput(loanAmountOut, bond, currency);
        return loanAmountOut;
    }

    /**
     * @dev Wraps the AMPL that was transferred to this contract and then approves loanRouter for entire amount
     * @param bond The bond that is being borrowed from
     * @return WAMPL balance that was wrapped. Equal to loanRouter allowance for WAMPL.
     */
    function _wamplWrap(uint256 underlyingAmount, IBondController bond) internal returns (uint256) {
        // Confirm that AMPL was sent
        require(underlyingAmount > 0, "WamplLoanRouter: No AMPL supplied");

        // Confirm that bond's collateral has WAMPL as underlying
        IButtonWrapper wrapper = IButtonWrapper(bond.collateralToken());
        require(wrapper.underlying() == address(wampl), "Collateral Token underlying does not match WAMPL address.");

        // Accessing AMPL contract from WAMPL
        IERC20 ampl = IERC20(wampl.underlying());

        // Transferring AMPL to contract
        SafeERC20.safeTransferFrom(ampl, msg.sender, address(this), underlyingAmount);

        // Wrapping contract's balance of AMPL into WAMPL
        SafeERC20.safeApprove(ampl, address(wampl), underlyingAmount);
        uint256 wamplAmount = wampl.deposit(underlyingAmount);

        // Approve loanRouter to take wampl
        wampl.approve(address(loanRouter), wamplAmount);
        return wamplAmount;
    }

    /**
     * @dev Distributes tranche balances and borrowed amounts to end-user
     * @param amountOut The output amount that is being borrowed
     * @param bond The bond that is being borrowed from
     * @param currency The asset being borrowed
     */
    function _distributeLoanOutput(
        uint256 amountOut,
        IBondController bond,
        IERC20 currency
    ) internal {
        // Send loan currenncy out from this contract to msg.sender
        SafeERC20.safeTransfer(currency, msg.sender, amountOut);

        // Send out the tranche tokens from this contract to the msg.sender
        ITranche tranche;
        for (uint256 i = 0; i < bond.trancheCount(); i++) {
            (tranche, ) = bond.tranches(i);
            SafeERC20.safeTransfer(tranche, msg.sender, tranche.balanceOf(address(this)));
        }
    }
}
