/**
 * HTTP Request Skill
 * 
 * Makes HTTP requests to external APIs with configurable options.
 */

import { z } from 'zod';
import { BaseSkill, SkillError, withTimeout, withRetry } from './base.js';

// SSRF Protection: Block internal/private network requests
const BLOCKED_HOSTS = [
  'localhost',
  '127.0.0.1',
  '0.0.0.0',
  '[::1]',
  '169.254.169.254',  // AWS/GCP metadata endpoint
  'metadata.google.internal',
];

const PRIVATE_IP_RANGES = [
  /^10\./,           // 10.0.0.0/8
  /^172\.(1[6-9]|2[0-9]|3[01])\./,  // 172.16.0.0/12
  /^192\.168\./,     // 192.168.0.0/16
  /^169\.254\./,     // Link-local
  /^127\./,          // Loopback
  /^0\./,            // Current network
];

function isBlockedUrl(urlString) {
  try {
    const url = new URL(urlString);
    const hostname = url.hostname.toLowerCase();
    
    // Check blocked hosts
    if (BLOCKED_HOSTS.includes(hostname)) {
      return true;
    }
    
    // Check private IP ranges
    for (const pattern of PRIVATE_IP_RANGES) {
      if (pattern.test(hostname)) {
        return true;
      }
    }
    
    // Block .local and .internal domains
    if (hostname.endsWith('.local') || hostname.endsWith('.internal')) {
      return true;
    }
    
    return false;
  } catch {
    return true; // Invalid URL, block it
  }
}

const inputSchema = z.object({
  url: z.string().url().describe('Request URL'),
  method: z.enum(['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'])
    .default('GET')
    .describe('HTTP method'),
  headers: z.record(z.string()).optional().describe('Request headers'),
  body: z.any().optional().describe('Request body (for POST/PUT/PATCH)'),
  query: z.record(z.string()).optional().describe('Query parameters'),
  timeout_ms: z.number().default(30000).describe('Request timeout in milliseconds'),
  retry: z.object({
    max_attempts: z.number().default(1),
    delay_ms: z.number().default(1000),
    backoff_multiplier: z.number().default(2)
  }).optional().describe('Retry configuration'),
  response_type: z.enum(['json', 'text', 'blob']).default('json')
    .describe('Expected response type')
});

const outputSchema = z.object({
  status: z.number(),
  status_text: z.string(),
  headers: z.record(z.string()),
  body: z.any(),
  timing: z.object({
    duration_ms: z.number()
  })
});

export class HttpRequestSkill extends BaseSkill {
  constructor() {
    super({
      name: 'http_request',
      description: 'Make HTTP requests to external APIs',
      version: '1.0.0',
      inputSchema,
      outputSchema,
      examples: [
        {
          description: 'Simple GET request',
          input: {
            url: 'https://api.example.com/users',
            method: 'GET'
          }
        },
        {
          description: 'POST with JSON body',
          input: {
            url: 'https://api.example.com/users',
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: { name: 'John', email: 'john@example.com' }
          }
        }
      ]
    });
  }

  async execute(input, context) {
    const {
      url,
      method,
      headers = {},
      body,
      query,
      timeout_ms,
      retry,
      response_type
    } = input;

    // Build URL with query parameters
    const requestUrl = this._buildUrl(url, query);

    // SSRF Protection: Block requests to internal/private networks
    if (isBlockedUrl(requestUrl)) {
      throw new SkillError(
        'SSRF_BLOCKED',
        `Request to internal/private network address is not allowed: ${new URL(requestUrl).hostname}`
      );
    }

    // Prepare fetch options
    const fetchOptions = {
      method,
      headers: { ...headers }
    };

    // Add body for methods that support it
    if (body && ['POST', 'PUT', 'PATCH'].includes(method)) {
      if (typeof body === 'object') {
        fetchOptions.body = JSON.stringify(body);
        if (!fetchOptions.headers['Content-Type']) {
          fetchOptions.headers['Content-Type'] = 'application/json';
        }
      } else {
        fetchOptions.body = body;
      }
    }

    // Execute request with timeout and optional retry
    const executeRequest = async () => {
      const startTime = Date.now();

      const response = await withTimeout(
        fetch(requestUrl, fetchOptions),
        timeout_ms
      );

      const duration = Date.now() - startTime;

      // Parse response based on type
      let responseBody;
      try {
        switch (response_type) {
          case 'json':
            responseBody = await response.json();
            break;
          case 'text':
            responseBody = await response.text();
            break;
          case 'blob':
            const buffer = await response.arrayBuffer();
            responseBody = Buffer.from(buffer).toString('base64');
            break;
        }
      } catch (e) {
        // If parsing fails, try to get text
        responseBody = await response.text().catch(() => null);
      }

      // Convert headers to object
      const responseHeaders = {};
      response.headers.forEach((value, key) => {
        responseHeaders[key] = value;
      });

      return {
        status: response.status,
        status_text: response.statusText,
        headers: responseHeaders,
        body: responseBody,
        timing: {
          duration_ms: duration
        }
      };
    };

    // Apply retry if configured
    if (retry && retry.max_attempts > 1) {
      return withRetry(executeRequest, {
        maxAttempts: retry.max_attempts,
        delayMs: retry.delay_ms,
        backoffMultiplier: retry.backoff_multiplier,
        shouldRetry: (error) => {
          // Retry on network errors and 5xx responses
          if (error.code === 'TIMEOUT') return true;
          if (error.name === 'TypeError') return true; // Network error
          return false;
        }
      });
    }

    return executeRequest();
  }

  _buildUrl(baseUrl, query) {
    if (!query || Object.keys(query).length === 0) {
      return baseUrl;
    }

    const url = new URL(baseUrl);
    for (const [key, value] of Object.entries(query)) {
      url.searchParams.append(key, value);
    }
    return url.toString();
  }
}
