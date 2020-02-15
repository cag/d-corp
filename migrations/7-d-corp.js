module.exports = (d) => d.deploy(
  artifacts.require('DCorp'),
  artifacts.require('WETH9').address,
  artifacts.require('UniswapFactory').address,
  artifacts.require('ConditionalTokens').address,
  artifacts.require('FPMMDeterministicFactory').address,
).then(async (dCorp) => {
  await dCorp.setup({ value: 1e18 });
});
