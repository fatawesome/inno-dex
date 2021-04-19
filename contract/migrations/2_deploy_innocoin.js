const InnoCoin = artifacts.require("InnoCoin");

module.exports = function (deployer) {
  deployer.deploy(InnoCoin);
};
