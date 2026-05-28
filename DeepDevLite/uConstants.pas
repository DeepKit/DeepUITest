unit uConstants;

interface

const
  APP_NAME = 'DeepDevLite';
  APP_VERSION = '1.0.0';
  
  MAX_FILE_SIZE = 500 * 1024;
  
  MAX_RETRY_COUNT = 3;
  
  DEFAULT_TIMEOUT_SEC = 120;
  TEST_TIMEOUT_SEC = 30;
  
  REPORT_WIDTH = 680;
  CARD_SIZE = 360;
  CARD_EXPORT_SIZE = 1080;
  
  GRID_SIZE = 28;
  
  COLOR_BRAND = $FF0D5C4A;
  COLOR_BRAND_LIGHT = $FF0F6E58;
  COLOR_ACCENT = $FF00E5A0;
  COLOR_BG = $FFF0F4F2;
  COLOR_SURFACE = $FFFFFFFF;
  COLOR_BORDER = $FFE0E8E4;
  COLOR_TEXT = $FF0F1F1A;
  COLOR_MUTED = $FF7A9088;
  COLOR_PASS = $FF0A7A56;
  COLOR_FAIL = $FFEF4444;
  COLOR_NIGHT_BG = $FF0A0F0E;
  
  MODEL_TIER_1 = 'claude-sonnet-4-6';
  MODEL_TIER_2 = 'claude-sonnet-4-6';
  MODEL_TIER_3 = 'claude-sonnet-4-6';
  
  DEFAULT_BASE_URL = 'http://localhost:8000';
  
  SUPPORTED_EXTENSIONS: array[0..13] of string = (
    '.py', '.js', '.ts', '.go', '.java', '.cs',
    '.rb', '.php', '.swift', '.kt', '.cpp', '.c',
    '.rs', '.dart'
  );

implementation

end.
