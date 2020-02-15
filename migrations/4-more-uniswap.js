module.exports = (d) => d.then(async () => {
  const factory = await artifacts.require('UniswapFactory').deployed();
  factory.initializeFactory(artifacts.require('UniswapExchange').address);
});
