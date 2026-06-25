"""InkFlow (墨韵) — fully automated literary text production engine."""

import logging

__version__ = "3.6.0"

# Package-level logger for services to use
logger = logging.getLogger("inkflow")
logger.addHandler(logging.NullHandler())