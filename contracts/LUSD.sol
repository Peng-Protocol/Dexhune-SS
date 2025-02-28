// SPDX-License-Identifier: BSD-3-Clause
/// @title LUSD ERC20 Root Implementation

pragma solidity ^0.8.28;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.1/contracts/token/ERC20/ERC20.sol";
import "./Ownable.sol";
import "./Normalizer.sol";
import "./interfaces/IAggregator.sol";
import "./interfaces/ILiquidity.sol";
import "./interfaces/IERC20.sol";
import "./libraries/PengMath.sol";

contract LUSD is ERC20, Normalizer, Ownable {
    address public taxCollector;

    ERC20Interface public tokenZero;
    IAggregator public oracle;
    ILiquidity public liquidity;

    uint8 internal _tokenZeroDec;
    uint8 internal _oracleDec;

    uint256 private constant INITIAL_SUPPLY = 4_000_000_000e18;
    uint256 private constant FEE_PERC = 5; // 0.05% fee

    event Taxed(address addr, uint256 amount);

    constructor() ERC20("Link Dollar", "LUSD") {
        _mint(_owner, INITIAL_SUPPLY);
    }

    function setLiquidity(address liquidityAddr) public onlyOwner {
        liquidity = ILiquidity(liquidityAddr);
        rebase();
    }

    function setTaxCollector(address taxAddr) public onlyOwner {
        taxCollector = taxAddr;
    }

    function setOracle(address oracleAddr) public onlyOwner {
        oracle = IAggregator(oracleAddr);

        try oracle.decimals() returns (uint8 dec) {
            _oracleDec = dec;
        } catch {
            _oracleDec = 8;
        }
    }

    function setTokenZero(address tokenZeroAddr) public onlyOwner {
        tokenZero = ERC20Interface(tokenZeroAddr);

        try tokenZero.decimals() returns (uint8 dec) {
            _tokenZeroDec = dec;
        } catch {
            _tokenZeroDec = 18;
        }
    }

    function initialize(
        address liquidityAddr,
        address oracleAddr,
        address tokenZeroAddr,
        address taxAddr
    ) external onlyOwner {
        require(address(liquidity) == address(0));
        require(address(tokenZero) == address(0));
        require(address(oracle) == address(0));
        require(taxCollector == address(0));

        setTaxCollector(taxAddr);
        setTokenZero(tokenZeroAddr);
        setOracle(oracleAddr);
        setLiquidity(liquidityAddr);
    }

    function getBalances()
        external
        view
        returns (uint256 balanceZero, uint256 balanceOne)
    {
        balanceZero = tokenZero.balanceOf(address(liquidity));
        balanceOne = balanceOf(address(liquidity));
    }

    function transfer(
        address to,
        uint256 value
    ) public virtual override returns (bool) {
        address from = _msgSender();

        value = _tax(from, value);
        _transfer(from, to, value);
        _trySync();

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);

        value = _tax(from, value);
        _transfer(from, to, value);
        _trySync();

        return true;
    }

    function approve(
        address spender,
        uint256 amount
    ) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        rebase();
        return true;
    }

    function _tax(address from, uint256 value) private returns (uint256) {
        address taxAcc = taxCollector;
        uint256 transferAmount = value;

        if (taxAcc == address(0)) {
            taxAcc = _owner;
        }

        if (taxAcc == address(0)) {
            return transferAmount;
        }

        uint256 fee = (value * FEE_PERC) / 10_000;
        (uint256 amount, bool negative) = _absDiff(value, fee);

        if (!negative && fee > 0) {
            transferAmount = amount;

            if (taxAcc != from) {
                _transfer(from, taxAcc, fee);
                _trySync();
            }

            emit Taxed(from, fee);
        }

        return transferAmount;
    }

    function _absDiff(
        uint256 v1,
        uint256 v2
    ) private pure returns (uint256 diff, bool negative) {
        if (v2 > v1) {
            uint256 tmp = v1;
            v1 = v2;
            v2 = tmp;
            negative = true;
        }

        diff = v1 - v2;
    }

    function getPrice() public view returns (int256) {
        return oracle.latestAnswer();
    }

    function _trySync() private {
        try liquidity.sync() {} catch {}
    }

    function _mustSync() private {
        liquidity.sync(); // Direct call, no try-catch, will revert on failure
    }

    function rebase() public {
        address liquidityAddress = address(liquidity);

        if (
            liquidityAddress == address(0) || address(tokenZero) == address(0)
        ) {
            return;
        }

        uint256 price = uint256(getPrice());
        uint256 balanceZero = tokenZero.balanceOf(liquidityAddress);
        uint256 balanceOne = balanceOf(liquidityAddress);

        uint256 nbalanceZero = _normalize(balanceZero, _tokenZeroDec);
        uint256 nprice = _normalize(price, _oracleDec);

        uint256 nlastRebase = PengMath.mul(nbalanceZero, nprice);
        uint256 nBalanceOne = _normalize(balanceOne, decimals());

        (uint256 nrebaseFactor, bool negative) = _absDiff(
            nlastRebase,
            nBalanceOne
        );

        uint256 rebaseFactor = _denormalize(nrebaseFactor, decimals());

        if (negative) {
            _burn(liquidityAddress, rebaseFactor);
        } else if (rebaseFactor > 0) {
            _mint(liquidityAddress, rebaseFactor);
        }

        _mustSync(); // Changed from _trySync to _mustSync to enforce sync or fail
    }
}
