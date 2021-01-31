pragma solidity 0.6.7;

contract TokenAuthority {
    address public root;
    modifier sudo { require(msg.sender == root); _; }
    event LogSetRoot(address indexed newRoot);
    function setRoot(address usr) public sudo {
        root = usr;
        emit LogSetRoot(usr);
    }

    mapping (address => uint) public wards;
    event LogRely(address indexed usr);
    function rely(address usr) public sudo { wards[usr] = 1; emit LogRely(usr); }
    event LogDeny(address indexed usr);
    function deny(address usr) public sudo { wards[usr] = 0; emit LogDeny(usr); }

    constructor() public {
        root = msg.sender;
    }

    // bytes4(keccak256(abi.encodePacked('burn(uint256)')))
    bytes4 constant burn = bytes4(0x42966c68);
    // bytes4(keccak256(abi.encodePacked('burn(address,uint256)')))
    bytes4 constant burnFrom = bytes4(0x9dc29fac);
    // bytes4(keccak256(abi.encodePacked('mint(address,uint256)')))
    bytes4 constant mint = bytes4(0x40c10f19);

    function canCall(address src, address, bytes4 sig)
    public view returns (bool)
    {
        if (sig == burn || sig == burnFrom || src == root) {
            return true;
        } else if (sig == mint) {
            return (wards[src] == 1);
        } else {
            return false;
        }
    }
}