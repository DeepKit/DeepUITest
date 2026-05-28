/**
 * Text Processing Skill
 * 
 * Various text transformation and analysis operations.
 */

import { z } from 'zod';
import { BaseSkill, SkillError } from './base.js';

const inputSchema = z.object({
  text: z.string().describe('Input text to process'),
  operation: z.enum([
    'uppercase',
    'lowercase',
    'capitalize',
    'trim',
    'split',
    'join',
    'replace',
    'extract',
    'count',
    'truncate',
    'template',
    'slugify',
    'hash'
  ]).describe('Text operation to perform'),
  options: z.object({
    separator: z.string().optional(),
    pattern: z.string().optional(),
    replacement: z.string().optional(),
    regex_flags: z.string().optional(),
    max_length: z.number().optional(),
    suffix: z.string().optional(),
    variables: z.record(z.any()).optional(),
    algorithm: z.enum(['md5', 'sha1', 'sha256']).optional()
  }).optional().describe('Operation-specific options')
});

const outputSchema = z.object({
  result: z.union([z.string(), z.number(), z.array(z.string())]),
  original_length: z.number(),
  result_length: z.number().optional()
});

export class TextProcessSkill extends BaseSkill {
  constructor() {
    super({
      name: 'text_process',
      description: 'Text transformation and analysis operations',
      version: '1.0.0',
      inputSchema,
      outputSchema,
      examples: [
        {
          description: 'Convert to uppercase',
          input: { text: 'hello world', operation: 'uppercase' },
          output: { result: 'HELLO WORLD', original_length: 11, result_length: 11 }
        },
        {
          description: 'Split text',
          input: { text: 'a,b,c', operation: 'split', options: { separator: ',' } },
          output: { result: ['a', 'b', 'c'], original_length: 5 }
        }
      ]
    });
  }

  async execute(input, context) {
    const { text, operation, options = {} } = input;
    const originalLength = text.length;

    let result;

    switch (operation) {
      case 'uppercase':
        result = text.toUpperCase();
        break;

      case 'lowercase':
        result = text.toLowerCase();
        break;

      case 'capitalize':
        result = text.replace(/\b\w/g, c => c.toUpperCase());
        break;

      case 'trim':
        result = text.trim();
        break;

      case 'split':
        result = text.split(options.separator || ' ');
        break;

      case 'join':
        // Expects text to be JSON array string
        try {
          const arr = JSON.parse(text);
          if (!Array.isArray(arr)) throw new Error('Input must be JSON array');
          result = arr.join(options.separator || ',');
        } catch (e) {
          throw new SkillError('INVALID_INPUT', 'Text must be a valid JSON array for join operation');
        }
        break;

      case 'replace':
        if (!options.pattern) {
          throw new SkillError('INVALID_OPTIONS', 'Pattern is required for replace operation');
        }
        const flags = options.regex_flags || 'g';
        const regex = new RegExp(options.pattern, flags);
        result = text.replace(regex, options.replacement || '');
        break;

      case 'extract':
        if (!options.pattern) {
          throw new SkillError('INVALID_OPTIONS', 'Pattern is required for extract operation');
        }
        const extractRegex = new RegExp(options.pattern, options.regex_flags || 'g');
        const matches = text.match(extractRegex);
        result = matches || [];
        break;

      case 'count':
        if (options.pattern) {
          const countRegex = new RegExp(options.pattern, 'g');
          const countMatches = text.match(countRegex);
          result = countMatches ? countMatches.length : 0;
        } else {
          // Count characters
          result = text.length;
        }
        break;

      case 'truncate':
        const maxLength = options.max_length || 100;
        const suffix = options.suffix || '...';
        if (text.length <= maxLength) {
          result = text;
        } else {
          result = text.slice(0, maxLength - suffix.length) + suffix;
        }
        break;

      case 'template':
        result = this._processTemplate(text, options.variables || {});
        break;

      case 'slugify':
        result = text
          .toLowerCase()
          .trim()
          .replace(/[^\w\s-]/g, '')
          .replace(/[\s_-]+/g, '-')
          .replace(/^-+|-+$/g, '');
        break;

      case 'hash':
        const crypto = await import('crypto');
        const algorithm = options.algorithm || 'sha256';
        result = crypto.createHash(algorithm).update(text).digest('hex');
        break;

      default:
        throw new SkillError('UNKNOWN_OPERATION', `Unknown operation: ${operation}`);
    }

    const output = {
      result,
      original_length: originalLength
    };

    if (typeof result === 'string') {
      output.result_length = result.length;
    }

    return output;
  }

  _processTemplate(template, variables) {
    return template.replace(/\{\{(\s*[\w.]+\s*)\}\}/g, (match, key) => {
      const trimmedKey = key.trim();
      const parts = trimmedKey.split('.');
      
      let value = variables;
      for (const part of parts) {
        if (value === null || value === undefined) return match;
        value = value[part];
      }
      
      return value !== undefined ? String(value) : match;
    });
  }
}
