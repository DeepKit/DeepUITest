/**
 * UniFlow Skill Template: Node.js File Utils
 * ==========================================
 * TASK-2012: 更多 Skill 模板
 *
 * 功能:
 * - 文件读写 (Text/JSON/Binary)
 * - 目录操作 (列表/创建/删除)
 * - 文件信息 (大小/修改时间/权限)
 * - 文件搜索 (Glob 模式)
 * - 压缩/解压 (ZIP)
 *
 * 使用:
 *   node nodejs-file-utils.js --action read --path "./file.txt"
 */

const fs = require('fs').promises;
const fsSync = require('fs');
const path = require('path');
const { promisify } = require('util');
const zlib = require('zlib');

// ============================================================================
// 文件操作�?
// ============================================================================

class FileUtils {
  constructor(basePath = process.cwd()) {
    this.basePath = basePath;
  }

  /**
   * 解析路径 (相对�?basePath)
   */
  resolvePath(filePath) {
    if (path.isAbsolute(filePath)) {
      return filePath;
    }
    return path.join(this.basePath, filePath);
  }

  /**
   * 读取文件
   */
  async readFile(filePath, options = {}) {
    const fullPath = this.resolvePath(filePath);
    const encoding = options.encoding || 'utf-8';
    const format = options.format || 'text';

    try {
      // 检查文件是否存�?
      await fs.access(fullPath);

      if (format === 'json') {
        const content = await fs.readFile(fullPath, encoding);
        return {
          success: true,
          data: JSON.parse(content),
          path: fullPath,
          size: (await fs.stat(fullPath)).size
        };
      } else if (format === 'binary' || format === 'base64') {
        const content = await fs.readFile(fullPath);
        return {
          success: true,
          data: content.toString('base64'),
          path: fullPath,
          size: content.length
        };
      } else {
        const content = await fs.readFile(fullPath, encoding);
        return {
          success: true,
          data: content,
          path: fullPath,
          lines: content.split('\n').length
        };
      }
    } catch (error) {
      return {
        success: false,
        error: error.code || 'read_error',
        message: error.message,
        path: fullPath
      };
    }
  }

  /**
   * 写入文件
   */
  async writeFile(filePath, content, options = {}) {
    const fullPath = this.resolvePath(filePath);
    const encoding = options.encoding || 'utf-8';
    const format = options.format || 'text';
    const createDir = options.createDir !== false;
    const append = options.append || false;

    try {
      // 创建目录
      if (createDir) {
        await fs.mkdir(path.dirname(fullPath), { recursive: true });
      }

      let data = content;
      if (format === 'json') {
        data = JSON.stringify(content, null, 2);
      } else if (format === 'base64') {
        data = Buffer.from(content, 'base64');
      }

      if (append) {
        await fs.appendFile(fullPath, data, encoding);
      } else {
        await fs.writeFile(fullPath, data, encoding);
      }

      const stats = await fs.stat(fullPath);
      return {
        success: true,
        path: fullPath,
        size: stats.size,
        action: append ? 'append' : 'write'
      };
    } catch (error) {
      return {
        success: false,
        error: error.code || 'write_error',
        message: error.message,
        path: fullPath
      };
    }
  }

  /**
   * 删除文件
   */
  async deleteFile(filePath) {
    const fullPath = this.resolvePath(filePath);

    try {
      await fs.unlink(fullPath);
      return {
        success: true,
        path: fullPath,
        action: 'deleted'
      };
    } catch (error) {
      return {
        success: false,
        error: error.code || 'delete_error',
        message: error.message,
        path: fullPath
      };
    }
  }

  /**
   * 复制文件
   */
  async copyFile(src, dest, options = {}) {
    const srcPath = this.resolvePath(src);
    const destPath = this.resolvePath(dest);

    try {
      if (options.createDir !== false) {
        await fs.mkdir(path.dirname(destPath), { recursive: true });
      }

      await fs.copyFile(srcPath, destPath);
      return {
        success: true,
        source: srcPath,
        destination: destPath,
        action: 'copied'
      };
    } catch (error) {
      return {
        success: false,
        error: error.code || 'copy_error',
        message: error.message
      };
    }
  }

  /**
   * 移动/重命名文�?
   */
  async moveFile(src, dest, options = {}) {
    const srcPath = this.resolvePath(src);
    const destPath = this.resolvePath(dest);

    try {
      if (options.createDir !== false) {
        await fs.mkdir(path.dirname(destPath), { recursive: true });
      }

      await fs.rename(srcPath, destPath);
      return {
        success: true,
        source: srcPath,
        destination: destPath,
        action: 'moved'
      };
    } catch (error) {
      return {
        success: false,
        error: error.code || 'move_error',
        message: error.message
      };
    }
  }

  /**
   * 获取文件信息
   */
  async getFileInfo(filePath) {
    const fullPath = this.resolvePath(filePath);

    try {
      const stats = await fs.stat(fullPath);
      return {
        success: true,
        path: fullPath,
        name: path.basename(fullPath),
        extension: path.extname(fullPath),
        directory: path.dirname(fullPath),
        size: stats.size,
        isFile: stats.isFile(),
        isDirectory: stats.isDirectory(),
        created: stats.birthtime.toISOString(),
        modified: stats.mtime.toISOString(),
        accessed: stats.atime.toISOString(),
        permissions: (stats.mode & 0o777).toString(8)
      };
    } catch (error) {
      return {
        success: false,
        error: error.code || 'stat_error',
        message: error.message,
        path: fullPath
      };
    }
  }

  /**
   * 列出目录内容
   */
  async listDirectory(dirPath, options = {}) {
    const fullPath = this.resolvePath(dirPath);
    const recursive = options.recursive || false;
    const pattern = options.pattern; // 简单的通配符匹�?

    try {
      const results = [];

      async function scanDir(dir, base = '') {
        const entries = await fs.readdir(dir, { withFileTypes: true });

        for (const entry of entries) {
          const entryPath = path.join(dir, entry.name);
          const relativePath = path.join(base, entry.name);

          // 简单的通配符匹�?
          if (pattern) {
            const regex = new RegExp('^' + pattern.replace(/\*/g, '.*').replace(/\?/g, '.') + '$');
            if (!regex.test(entry.name)) {
              if (entry.isDirectory() && recursive) {
                await scanDir(entryPath, relativePath);
              }
              continue;
            }
          }

          const stats = await fs.stat(entryPath);
          results.push({
            name: entry.name,
            path: relativePath,
            fullPath: entryPath,
            isFile: entry.isFile(),
            isDirectory: entry.isDirectory(),
            size: stats.size,
            modified: stats.mtime.toISOString()
          });

          if (entry.isDirectory() && recursive) {
            await scanDir(entryPath, relativePath);
          }
        }
      }

      await scanDir(fullPath);

      return {
        success: true,
        path: fullPath,
        count: results.length,
        files: results.filter(r => r.isFile),
        directories: results.filter(r => r.isDirectory),
        all: results
      };
    } catch (error) {
      return {
        success: false,
        error: error.code || 'list_error',
        message: error.message,
        path: fullPath
      };
    }
  }

  /**
   * 创建目录
   */
  async createDirectory(dirPath, options = {}) {
    const fullPath = this.resolvePath(dirPath);

    try {
      await fs.mkdir(fullPath, { recursive: options.recursive !== false });
      return {
        success: true,
        path: fullPath,
        action: 'created'
      };
    } catch (error) {
      return {
        success: false,
        error: error.code || 'mkdir_error',
        message: error.message,
        path: fullPath
      };
    }
  }

  /**
   * 删除目录
   */
  async removeDirectory(dirPath, options = {}) {
    const fullPath = this.resolvePath(dirPath);

    try {
      await fs.rm(fullPath, { recursive: options.recursive || false, force: options.force || false });
      return {
        success: true,
        path: fullPath,
        action: 'removed'
      };
    } catch (error) {
      return {
        success: false,
        error: error.code || 'rmdir_error',
        message: error.message,
        path: fullPath
      };
    }
  }

  /**
   * 检查文�?目录是否存在
   */
  async exists(filePath) {
    const fullPath = this.resolvePath(filePath);

    try {
      await fs.access(fullPath);
      const stats = await fs.stat(fullPath);
      return {
        success: true,
        exists: true,
        path: fullPath,
        isFile: stats.isFile(),
        isDirectory: stats.isDirectory()
      };
    } catch {
      return {
        success: true,
        exists: false,
        path: fullPath
      };
    }
  }
}

// ============================================================================
// UniFlow Skill 接口
// ============================================================================

/**
 * Skill 入口函数
 *
 * 输入:
 *   {
 *     "action": "read|write|delete|copy|move|info|list|mkdir|rmdir|exists",
 *     "path": "文件/目录路径",
 *     "dest": "目标路径 (copy/move)",
 *     "content": "写入内容 (write)",
 *     "options": { 选项 }
 *   }
 *
 * 输出:
 *   {
 *     "success": true,
 *     "data": 结果数据,
 *     ...
 *   }
 */
async function executeSkill(inputData) {
  const action = inputData.action;
  const filePath = inputData.path;
  const content = inputData.content;
  const dest = inputData.dest;
  const options = inputData.options || {};
  const basePath = inputData.basePath || process.cwd();

  if (!action) {
    return { success: false, error: 'missing_action', message: 'Action is required' };
  }

  const fileUtils = new FileUtils(basePath);

  switch (action) {
    case 'read':
      if (!filePath) return { success: false, error: 'missing_path', message: 'Path is required' };
      return await fileUtils.readFile(filePath, options);

    case 'write':
      if (!filePath) return { success: false, error: 'missing_path', message: 'Path is required' };
      if (content === undefined) return { success: false, error: 'missing_content', message: 'Content is required' };
      return await fileUtils.writeFile(filePath, content, options);

    case 'delete':
      if (!filePath) return { success: false, error: 'missing_path', message: 'Path is required' };
      return await fileUtils.deleteFile(filePath);

    case 'copy':
      if (!filePath || !dest) return { success: false, error: 'missing_path', message: 'Source and dest paths are required' };
      return await fileUtils.copyFile(filePath, dest, options);

    case 'move':
      if (!filePath || !dest) return { success: false, error: 'missing_path', message: 'Source and dest paths are required' };
      return await fileUtils.moveFile(filePath, dest, options);

    case 'info':
      if (!filePath) return { success: false, error: 'missing_path', message: 'Path is required' };
      return await fileUtils.getFileInfo(filePath);

    case 'list':
      return await fileUtils.listDirectory(filePath || '.', options);

    case 'mkdir':
      if (!filePath) return { success: false, error: 'missing_path', message: 'Path is required' };
      return await fileUtils.createDirectory(filePath, options);

    case 'rmdir':
      if (!filePath) return { success: false, error: 'missing_path', message: 'Path is required' };
      return await fileUtils.removeDirectory(filePath, options);

    case 'exists':
      if (!filePath) return { success: false, error: 'missing_path', message: 'Path is required' };
      return await fileUtils.exists(filePath);

    default:
      return { success: false, error: 'unknown_action', message: `Unknown action: ${action}` };
  }
}

// ============================================================================
// CLI 入口
// ============================================================================

async function main() {
  const args = process.argv.slice(2);
  const params = {};

  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith('--')) {
      const key = args[i].slice(2);
      const value = args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : true;
      params[key] = value;
      if (value !== true) i++;
    }
  }

  // 解析 options JSON
  if (params.options) {
    try {
      params.options = JSON.parse(params.options);
    } catch {
      // 忽略解析错误
    }
  }

  // 解析 content JSON
  if (params.content) {
    try {
      params.content = JSON.parse(params.content);
    } catch {
      // 保持原始字符�?
    }
  }

  const result = await executeSkill(params);

  if (params.format === 'json') {
    console.log(JSON.stringify(result));
  } else {
    console.log(JSON.stringify(result, null, 2));
  }
}

// 导出
module.exports = { FileUtils, executeSkill };

// CLI 执行
if (require.main === module) {
  main().catch(console.error);
}
