module.exports = (d) => d.deploy(
  artifacts.require('DCorp'),
  artifacts.require('UniswapFactory').address,
  artifacts.require('WETH9').address,
);
