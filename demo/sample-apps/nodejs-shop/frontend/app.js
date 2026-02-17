// Simple Express.js frontend - NO OpenTelemetry SDK code!
// Auto-instrumentation happens via OTel Operator annotation

const express = require('express');
const axios = require('axios');

const app = express();
const PORT = process.env.PORT || 3000;
const PRODUCT_API_URL = process.env.PRODUCT_API_URL || 'http://product-api:3001';

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', service: 'frontend' });
});

// Homepage
app.get('/', async (req, res) => {
  try {
    const response = await axios.get(`${PRODUCT_API_URL}/products`);
    const products = response.data;

    res.status(200).json({
      service: 'frontend',
      message: 'E-commerce shop frontend',
      products: products,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('Error fetching products:', error.message);
    res.status(500).json({
      error: 'Failed to fetch products',
      message: error.message
    });
  }
});

// Product detail page
app.get('/product/:id', async (req, res) => {
  const { id } = req.params;

  try {
    const response = await axios.get(`${PRODUCT_API_URL}/product/${id}`);
    const product = response.data;

    res.status(200).json({
      service: 'frontend',
      product: product,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error(`Error fetching product ${id}:`, error.message);
    res.status(500).json({
      error: 'Failed to fetch product',
      message: error.message
    });
  }
});

// Intentional error endpoint for demo
app.get('/error', (req, res) => {
  console.error('Intentional error triggered for demo');
  res.status(500).json({
    error: 'Intentional error',
    message: 'This endpoint always returns 500 to demonstrate error tracking'
  });
});

// Start server
app.listen(PORT, () => {
  console.log(`Frontend service listening on port ${PORT}`);
  console.log(`Product API URL: ${PRODUCT_API_URL}`);
});
