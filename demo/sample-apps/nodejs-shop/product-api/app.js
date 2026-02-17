const express = require('express');
const axios = require('axios');

const app = express();
const PORT = process.env.PORT || 3001;
const INVENTORY_URL = process.env.INVENTORY_URL || 'http://inventory:3002';

const products = [
  { id: 1, name: 'Solar Panel 400W', price: 299.99, category: 'solar' },
  { id: 2, name: 'Battery Storage 10kWh', price: 7999.99, category: 'storage' },
  { id: 3, name: 'Inverter 5kW', price: 1499.99, category: 'inverter' },
];

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', service: 'product-api' });
});

app.get('/products', async (req, res) => {
  try {
    // Simulate database query delay
    await new Promise(resolve => setTimeout(resolve, Math.random() * 100));

    // Check inventory for each product
    const productsWithInventory = await Promise.all(
      products.map(async (product) => {
        try {
          const inventoryResponse = await axios.get(`${INVENTORY_URL}/inventory/${product.id}`);
          return { ...product, stock: inventoryResponse.data.stock };
        } catch (error) {
          console.error(`Error fetching inventory for product ${product.id}`);
          return { ...product, stock: 0 };
        }
      })
    );

    res.status(200).json(productsWithInventory);
  } catch (error) {
    console.error('Error in /products:', error.message);
    res.status(500).json({ error: 'Failed to fetch products' });
  }
});

app.get('/product/:id', async (req, res) => {
  const { id } = req.params;
  const product = products.find(p => p.id === parseInt(id));

  if (!product) {
    return res.status(404).json({ error: 'Product not found' });
  }

  try {
    const inventoryResponse = await axios.get(`${INVENTORY_URL}/inventory/${id}`);
    res.status(200).json({ ...product, stock: inventoryResponse.data.stock });
  } catch (error) {
    console.error(`Error fetching inventory for product ${id}`);
    res.status(200).json({ ...product, stock: 0 });
  }
});

app.listen(PORT, () => {
  console.log(`Product API listening on port ${PORT}`);
});
