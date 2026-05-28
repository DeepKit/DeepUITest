/**
 * Base Skill class for UniFlow Node.js Skills
 * 
 * All skills should extend this class and implement the execute method.
 */

import { z } from 'zod';

/**
 * Abstract base class for skills
 */
export class BaseSkill {
  /**
   * @param {Object} config Skill configuration
   * @param {string} config.name Skill name (unique identifier)
   * @param {string} config.description Human-readable description
   * @param {string} config.version Skill version
   * @param {z.ZodSchema} config.inputSchema Zod schema for input validation
   * @param {z.ZodSchema} config.outputSchema Zod schema for output validation
   */
  constructor(config) {
    this.name = config.name;
    this.description = config.description;
    this.version = config.version || '1.0.0';
    this._inputSchema = config.inputSchema;
    this._outputSchema = config.outputSchema;
    this.examples = config.examples || [];
  }

  /**
   * Get JSON Schema representation of input schema
   */
  get inputSchema() {
    return this._zodToJsonSchema(this._inputSchema);
  }

  /**
   * Get JSON Schema representation of output schema
   */
  get outputSchema() {
    return this._zodToJsonSchema(this._outputSchema);
  }

  /**
   * Validate input against schema
   * @param {any} input Input data to validate
   * @returns {{ valid: boolean, errors?: string[] }}
   */
  validateInput(input) {
    try {
      this._inputSchema.parse(input);
      return { valid: true };
    } catch (error) {
      if (error instanceof z.ZodError) {
        return {
          valid: false,
          errors: error.errors.map(e => `${e.path.join('.')}: ${e.message}`)
        };
      }
      return { valid: false, errors: [error.message] };
    }
  }

  /**
   * Validate output against schema
   * @param {any} output Output data to validate
   * @returns {{ valid: boolean, errors?: string[] }}
   */
  validateOutput(output) {
    try {
      this._outputSchema.parse(output);
      return { valid: true };
    } catch (error) {
      if (error instanceof z.ZodError) {
        return {
          valid: false,
          errors: error.errors.map(e => `${e.path.join('.')}: ${e.message}`)
        };
      }
      return { valid: false, errors: [error.message] };
    }
  }

  /**
   * Execute the skill
   * @param {any} input Validated input data
   * @param {Object} context Execution context
   * @returns {Promise<any>} Skill result
   */
  async execute(input, context) {
    throw new Error('execute() must be implemented by subclass');
  }

  /**
   * Convert Zod schema to simplified JSON Schema (for documentation)
   * @private
   */
  _zodToJsonSchema(schema) {
    if (!schema) return {};
    
    // Simple conversion - in production, use zod-to-json-schema
    const def = schema._def;
    
    if (def.typeName === 'ZodObject') {
      const properties = {};
      const required = [];
      
      for (const [key, value] of Object.entries(def.shape())) {
        properties[key] = this._zodToJsonSchema(value);
        if (!value.isOptional()) {
          required.push(key);
        }
      }
      
      return {
        type: 'object',
        properties,
        required: required.length > 0 ? required : undefined
      };
    }
    
    if (def.typeName === 'ZodString') {
      return { type: 'string' };
    }
    
    if (def.typeName === 'ZodNumber') {
      return { type: 'number' };
    }
    
    if (def.typeName === 'ZodBoolean') {
      return { type: 'boolean' };
    }
    
    if (def.typeName === 'ZodArray') {
      return {
        type: 'array',
        items: this._zodToJsonSchema(def.type)
      };
    }
    
    if (def.typeName === 'ZodOptional') {
      return this._zodToJsonSchema(def.innerType);
    }
    
    if (def.typeName === 'ZodDefault') {
      const inner = this._zodToJsonSchema(def.innerType);
      inner.default = def.defaultValue();
      return inner;
    }
    
    if (def.typeName === 'ZodEnum') {
      return {
        type: 'string',
        enum: def.values
      };
    }
    
    if (def.typeName === 'ZodUnion') {
      return {
        oneOf: def.options.map(opt => this._zodToJsonSchema(opt))
      };
    }
    
    if (def.typeName === 'ZodAny') {
      return {};
    }
    
    return { type: 'unknown' };
  }
}

/**
 * Skill execution error
 */
export class SkillError extends Error {
  constructor(code, message, details = null) {
    super(message);
    this.name = 'SkillError';
    this.code = code;
    this.details = details;
  }
}

/**
 * Input validation error
 */
export class ValidationError extends SkillError {
  constructor(message, errors) {
    super('VALIDATION_ERROR', message, errors);
    this.name = 'ValidationError';
  }
}

/**
 * Timeout error
 */
export class TimeoutError extends SkillError {
  constructor(timeoutMs) {
    super('TIMEOUT', `Operation timed out after ${timeoutMs}ms`);
    this.name = 'TimeoutError';
  }
}

/**
 * Helper to execute with timeout
 * @param {Promise} promise Promise to execute
 * @param {number} timeoutMs Timeout in milliseconds
 * @returns {Promise}
 */
export async function withTimeout(promise, timeoutMs) {
  let timeoutId;
  
  const timeoutPromise = new Promise((_, reject) => {
    timeoutId = setTimeout(() => {
      reject(new TimeoutError(timeoutMs));
    }, timeoutMs);
  });
  
  try {
    return await Promise.race([promise, timeoutPromise]);
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * Helper to retry failed operations
 * @param {Function} fn Function to retry
 * @param {Object} options Retry options
 * @returns {Promise}
 */
export async function withRetry(fn, options = {}) {
  const {
    maxAttempts = 3,
    delayMs = 1000,
    backoffMultiplier = 2,
    shouldRetry = () => true
  } = options;
  
  let lastError;
  let delay = delayMs;
  
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn(attempt);
    } catch (error) {
      lastError = error;
      
      if (attempt === maxAttempts || !shouldRetry(error)) {
        throw error;
      }
      
      await new Promise(resolve => setTimeout(resolve, delay));
      delay *= backoffMultiplier;
    }
  }
  
  throw lastError;
}
