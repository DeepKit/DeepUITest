"""
插件机制 �?支持自定义验证规则插�?"""

from __future__ import annotations
from abc import ABC, abstractmethod
from typing import Any


class OddPlugin(ABC):
    """所�?odd 插件的基�?""

    #: 插件唯一标识，子类必须覆�?    name: str = ""
    #: 简短描�?    description: str = ""

    @abstractmethod
    def verify(self, code: str, contract: dict) -> list[dict]:
        """
        执行自定义验证逻辑�?
        Parameters
        ----------
        code:     被验证的源代码字符串
        contract: 完整契约 dict（含 verification_hints 等字段）

        Returns
        -------
        checks: list of dicts, 每项格式�?            {
                "type":     str,   # 规则类型标识
                "rule":     str,   # 规则描述
                "severity": str,   # "critical" | "medium" | "low"
                "passed":   bool,
                "found":    Any,   # 匹配到的内容，未匹配�?None
            }
        """


class PluginRegistry:
    """全局插件注册表（单例�?""

    _plugins: dict[str, OddPlugin] = {}

    @classmethod
    def register(cls, plugin: OddPlugin) -> None:
        if not plugin.name:
            raise ValueError(f"插件 {type(plugin).__name__} 未设�?name 属�?)
        cls._plugins[plugin.name] = plugin

    @classmethod
    def get(cls, name: str) -> OddPlugin | None:
        return cls._plugins.get(name)

    @classmethod
    def all(cls) -> list[OddPlugin]:
        return list(cls._plugins.values())

    @classmethod
    def clear(cls) -> None:
        cls._plugins.clear()


def register_plugin(plugin: OddPlugin) -> None:
    """便捷注册函数"""
    PluginRegistry.register(plugin)


def load_plugins_from_dir(plugins_dir: str) -> int:
    """
    从目录动态加载插件模块（每个 .py 文件视为一个插件模块）�?    返回成功加载的插件数量�?    """
    import importlib.util
    from pathlib import Path

    loaded = 0
    for py_file in Path(plugins_dir).glob("*.py"):
        if py_file.name.startswith("_"):
            continue
        spec = importlib.util.spec_from_file_location(py_file.stem, py_file)
        if spec and spec.loader:
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)  # type: ignore[arg-type]
            loaded += 1
    return loaded
