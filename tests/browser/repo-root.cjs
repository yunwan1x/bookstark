// Test fixtures and application assets are always resolved from the checkout.
// This does not change the working directory of the Go test server process.
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
process.chdir(root);
module.exports = root;
