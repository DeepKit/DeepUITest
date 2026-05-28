def generate_svg(badge) -> str:
    """Generate SVG badge for DeepDevLite verification."""
    
    pass_rate = badge.pass_rate
    
    if pass_rate == 100:
        color = "#00E5A0"
        bg_color = "#0D5C4A"
    elif pass_rate >= 80:
        color = "#00E5A0"
        bg_color = "#0D5C4A"
    elif pass_rate >= 60:
        color = "#FFA500"
        bg_color = "#8B4513"
    else:
        color = "#EF4444"
        bg_color = "#7F1D1D"
    
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="280" height="64" viewBox="0 0 280 64">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:{bg_color};stop-opacity:1" />
      <stop offset="100%" style="stop-color:{bg_color}dd;stop-opacity:1" />
    </linearGradient>
  </defs>
  
  <rect width="280" height="64" rx="8" fill="url(#bg)"/>
  
  <text x="16" y="24" font-family="monospace" font-size="10" fill="{color}" opacity="0.8">
    DeepDevLite VERIFIED
  </text>
  
  <text x="16" y="44" font-family="sans-serif" font-size="14" fill="white" font-weight="bold">
    {badge.project_name[:20]}{'...' if len(badge.project_name) > 20 else ''}
  </text>
  
  <text x="200" y="36" font-family="monospace" font-size="16" fill="{color}">
    {badge.scenario_pass}/{badge.scenario_total}
  </text>
  
  <circle cx="260" cy="32" r="12" fill="{color}" opacity="0.2"/>
  <circle cx="260" cy="32" r="8" fill="{color}"/>
  <text x="256" y="36" font-family="sans-serif" font-size="12" fill="{bg_color}" font-weight="bold">
    �?  </text>
</svg>'''
    
    return svg
