const express = require('express');

const app = express();
const PORT = process.env.PORT || 3002;

const inventory = {
  1: { stock: 150 },
  2: { stock: 25 },
  3: { stock: 80 },
};

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', service: 'inventory' });
});

app.get('/inventory/:productId', (req, res) => {
  const { productId } = req.params;
  const stock = inventory[productId];

  // Simulate database query delay
  setTimeout(() => {
    if (stock) {
      res.status(200).json({ productId: parseInt(productId), stock: stock.stock });
    } else {
      res.status(404).json({ error: 'Product not found in inventory' });
    }
  }, Math.random() * 50);
});

app.listen(PORT, () => {
  console.log(`Inventory service listening on port ${PORT}`);
});
