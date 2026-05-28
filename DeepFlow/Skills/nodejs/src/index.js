/**
 * UniFlow Node.js Skill Service
 * 
 * A lightweight skill execution service compatible with UniFlow workflow engine.
 * Provides REST API for skill discovery, invocation, and health monitoring.
 */

import express from 'express';
import { v4 as uuidv4 } from 'uuid';
import dotenv from 'dotenv';
import { createLogger, format, transports } from 'winston';
import { SkillRegistry } from './skills/registry.js';
import { JsonTransformSkill } from './skills/json-transform.js';
import { HttpRequestSkill } from './skills/http-request.js';
import { TextProcessSkill } from './skills/text-process.js';

// Load environment variables
dotenv.config();

// Configuration
const PORT = process.env.PORT || 8081;
const HOST = process.env.HOST || '0.0.0.0';
const LOG_LEVEL = process.env.LOG_LEVEL || 'info';

// Logger setup
const logger = createLogger({
  level: LOG_LEVEL,
  format: format.combine(
    format.timestamp(),
    format.errors({ stack: true }),
    format.json()
  ),
  transports: [
    new transports.Console({
      format: format.combine(
        format.colorize(),
        format.simple()
      )
    })
  ]
});

// Initialize Express app
const app = express();
app.use(express.json({ limit: '10mb' }));

// Request logging middleware
app.use((req, res, next) => {
  const requestId = uuidv4();
  req.requestId = requestId;
  res.setHeader('X-Request-ID', requestId);
  
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    logger.info({
      requestId,
      method: req.method,
      path: req.path,
      status: res.statusCode,
      duration: `${duration}ms`
    });
  });
  
  next();
});

// Initialize skill registry
const registry = new SkillRegistry(logger);

// Register built-in skills
registry.register(new JsonTransformSkill());
registry.register(new HttpRequestSkill());
registry.register(new TextProcessSkill());

// ============================================================================
// Health & Info Endpoints
// ============================================================================

/**
 * Health check endpoint
 */
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    version: '1.0.0',
    runtime: 'nodejs',
    skills: registry.count()
  });
});

/**
 * Service info endpoint
 */
app.get('/info', (req, res) => {
  res.json({
    name: 'UniFlow Node.js Skill Service',
    version: '1.0.0',
    runtime: {
      platform: 'nodejs',
      version: process.version
    },
    skills: registry.listSkills()
  });
});

// ============================================================================
// Skill Discovery Endpoints
// ============================================================================

/**
 * List all available skills
 */
app.get('/skills', (req, res) => {
  const skills = registry.listSkills().map(skill => ({
    name: skill.name,
    description: skill.description,
    version: skill.version,
    inputSchema: skill.inputSchema,
    outputSchema: skill.outputSchema
  }));
  
  res.json({ skills });
});

/**
 * Get skill details
 */
app.get('/skills/:name', (req, res) => {
  const skill = registry.get(req.params.name);
  
  if (!skill) {
    return res.status(404).json({
      error: 'SkillNotFound',
      message: `Skill '${req.params.name}' not found`
    });
  }
  
  res.json({
    name: skill.name,
    description: skill.description,
    version: skill.version,
    inputSchema: skill.inputSchema,
    outputSchema: skill.outputSchema,
    examples: skill.examples || []
  });
});

// ============================================================================
// Skill Execution Endpoints
// ============================================================================

/**
 * Execute a skill
 */
app.post('/skills/:name/execute', async (req, res) => {
  const { name } = req.params;
  const { input, context = {} } = req.body;
  
  const skill = registry.get(name);
  
  if (!skill) {
    return res.status(404).json({
      success: false,
      error: {
        code: 'SKILL_NOT_FOUND',
        message: `Skill '${name}' not found`
      }
    });
  }
  
  const startTime = Date.now();
  
  try {
    // Validate input
    const validationResult = skill.validateInput(input);
    if (!validationResult.valid) {
      return res.status(400).json({
        success: false,
        error: {
          code: 'INVALID_INPUT',
          message: 'Input validation failed',
          details: validationResult.errors
        }
      });
    }
    
    // Execute skill
    logger.debug({ requestId: req.requestId, skill: name, input });
    
    const result = await skill.execute(input, {
      ...context,
      requestId: req.requestId,
      logger
    });
    
    const duration = Date.now() - startTime;
    
    res.json({
      success: true,
      result,
      metadata: {
        skill: name,
        duration_ms: duration,
        request_id: req.requestId
      }
    });
    
  } catch (error) {
    const duration = Date.now() - startTime;
    
    logger.error({
      requestId: req.requestId,
      skill: name,
      error: error.message,
      stack: error.stack
    });
    
    res.status(500).json({
      success: false,
      error: {
        code: error.code || 'EXECUTION_ERROR',
        message: error.message
      },
      metadata: {
        skill: name,
        duration_ms: duration,
        request_id: req.requestId
      }
    });
  }
});

/**
 * Batch execute multiple skills
 */
app.post('/batch/execute', async (req, res) => {
  const { tasks } = req.body;
  
  if (!Array.isArray(tasks) || tasks.length === 0) {
    return res.status(400).json({
      success: false,
      error: {
        code: 'INVALID_REQUEST',
        message: 'Tasks array is required'
      }
    });
  }
  
  const results = await Promise.all(
    tasks.map(async (task, index) => {
      const { skill: skillName, input, context = {} } = task;
      const skill = registry.get(skillName);
      
      if (!skill) {
        return {
          index,
          success: false,
          error: { code: 'SKILL_NOT_FOUND', message: `Skill '${skillName}' not found` }
        };
      }
      
      try {
        const startTime = Date.now();
        const result = await skill.execute(input, { ...context, logger });
        return {
          index,
          success: true,
          result,
          duration_ms: Date.now() - startTime
        };
      } catch (error) {
        return {
          index,
          success: false,
          error: { code: error.code || 'EXECUTION_ERROR', message: error.message }
        };
      }
    })
  );
  
  res.json({
    success: results.every(r => r.success),
    results,
    metadata: {
      total: tasks.length,
      succeeded: results.filter(r => r.success).length,
      failed: results.filter(r => !r.success).length
    }
  });
});

// ============================================================================
// Error Handling
// ============================================================================

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'NotFound',
    message: `Route ${req.method} ${req.path} not found`
  });
});

// Error handler
app.use((err, req, res, next) => {
  logger.error({
    requestId: req.requestId,
    error: err.message,
    stack: err.stack
  });
  
  res.status(500).json({
    error: 'InternalServerError',
    message: process.env.NODE_ENV === 'production' 
      ? 'An internal error occurred' 
      : err.message
  });
});

// ============================================================================
// Start Server
// ============================================================================

app.listen(PORT, HOST, () => {
  logger.info(`UniFlow Node.js Skill Service started on http://${HOST}:${PORT}`);
  logger.info(`Registered skills: ${registry.listSkills().map(s => s.name).join(', ')}`);
});

export { app, registry };
