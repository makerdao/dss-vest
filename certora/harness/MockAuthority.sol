pragma solidity 0.6.12;

interface DSAuthority {
    function canCall(
        address src, address dst, bytes4 sig
    ) external view returns (bool);
}
contract MockAuthority is DSAuthority {
    mapping (address => mapping (address => mapping (bytes4 => bool))) public override canCall;
}
