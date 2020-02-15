module.exports = (d) => [
  'UniswapExchange',
  'UniswapFactory',
].forEach(c => d.deploy(artifacts.require(c)));
