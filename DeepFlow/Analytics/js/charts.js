/**
 * UniFlow Analytics Dashboard - Chart Library (Pure SVG)
 */

const Charts = {
  // Chart color palette (Catppuccin)
  colors: {
    primary: '#89b4fa',
    success: '#a6e3a1',
    error: '#f38ba8',
    warning: '#f9e2af',
    info: '#74c7ec',
    surface: '#313244',
    text: '#cdd6f4',
    muted: '#7f849c'
  },

  // ===== Line Chart =====
  
  /**
   * Create a line chart with optional area fill
   * @param {HTMLElement} container - Target container element
   * @param {Object} options - Chart configuration
   */
  lineChart(container, options) {
    const {
      data = [],          // Array of { x, y, label? }
      series = null,      // For multi-series: [{ name, data, color }]
      width = null,
      height = null,
      showArea = true,
      showPoints = true,
      showGrid = true,
      showTooltip = true,
      animate = true,
      yMin = null,
      yMax = null,
      xAxisFormatter = null,
      yAxisFormatter = null,
      colorClass = 'primary'
    } = options;

    const rect = container.getBoundingClientRect();
    const w = width || rect.width || 400;
    const h = height || rect.height || 200;
    const padding = { top: 20, right: 20, bottom: 30, left: 50 };
    const chartW = w - padding.left - padding.right;
    const chartH = h - padding.top - padding.bottom;

    // Prepare data
    const allSeries = series || [{ name: 'default', data, colorClass }];
    const allPoints = allSeries.flatMap(s => s.data);
    
    if (allPoints.length === 0) {
      container.innerHTML = `<div class="chart-empty"><span class="chart-empty-icon">📊</span><span class="chart-empty-text">No data available</span></div>`;
      return;
    }

    // Calculate scales
    const xValues = allPoints.map(d => d.x);
    const yValues = allPoints.map(d => d.y);
    const xMin = Math.min(...xValues);
    const xMax = Math.max(...xValues);
    const dataYMin = Math.min(...yValues);
    const dataYMax = Math.max(...yValues);
    const yMinFinal = yMin !== null ? yMin : Math.max(0, dataYMin * 0.9);
    const yMaxFinal = yMax !== null ? yMax : dataYMax * 1.1 || 1;

    const scaleX = (x) => padding.left + ((x - xMin) / (xMax - xMin || 1)) * chartW;
    const scaleY = (y) => padding.top + chartH - ((y - yMinFinal) / (yMaxFinal - yMinFinal || 1)) * chartH;

    // Create SVG
    const svg = Utils.createSVGElement('svg', {
      class: 'chart-svg',
      viewBox: `0 0 ${w} ${h}`,
      preserveAspectRatio: 'xMidYMid meet'
    });

    // Grid lines
    if (showGrid) {
      const gridGroup = Utils.createSVGElement('g', { class: 'chart-grid' });
      const yTicks = 5;
      for (let i = 0; i <= yTicks; i++) {
        const y = padding.top + (chartH / yTicks) * i;
        const line = Utils.createSVGElement('line', {
          x1: padding.left, y1: y,
          x2: w - padding.right, y2: y
        });
        gridGroup.appendChild(line);
      }
      svg.appendChild(gridGroup);
    }

    // Axes
    const axisGroup = Utils.createSVGElement('g', { class: 'chart-axis' });
    
    // Y-axis labels
    const yTicks = 5;
    for (let i = 0; i <= yTicks; i++) {
      const yVal = yMinFinal + ((yMaxFinal - yMinFinal) / yTicks) * (yTicks - i);
      const y = padding.top + (chartH / yTicks) * i;
      const label = yAxisFormatter ? yAxisFormatter(yVal) : Math.round(yVal).toString();
      const text = Utils.createSVGElement('text', {
        x: padding.left - 8, y: y + 4,
        'text-anchor': 'end'
      });
      text.textContent = label;
      axisGroup.appendChild(text);
    }

    // X-axis labels
    const xTicks = Math.min(6, allSeries[0].data.length);
    const xStep = Math.ceil(allSeries[0].data.length / xTicks);
    allSeries[0].data.forEach((d, i) => {
      if (i % xStep === 0 || i === allSeries[0].data.length - 1) {
        const x = scaleX(d.x);
        const label = d.label || (xAxisFormatter ? xAxisFormatter(d.x) : d.x.toString());
        const text = Utils.createSVGElement('text', {
          x, y: h - padding.bottom + 20,
          'text-anchor': 'middle'
        });
        text.textContent = label;
        axisGroup.appendChild(text);
      }
    });
    svg.appendChild(axisGroup);

    // Draw each series
    allSeries.forEach((s, si) => {
      const seriesData = s.data;
      const color = s.colorClass || colorClass;
      
      if (seriesData.length === 0) return;

      // Build path
      const pathD = seriesData.map((d, i) => {
        const x = scaleX(d.x);
        const y = scaleY(d.y);
        return `${i === 0 ? 'M' : 'L'} ${x} ${y}`;
      }).join(' ');

      // Area fill
      if (showArea) {
        const areaD = pathD + 
          ` L ${scaleX(seriesData[seriesData.length - 1].x)} ${padding.top + chartH}` +
          ` L ${scaleX(seriesData[0].x)} ${padding.top + chartH} Z`;
        const area = Utils.createSVGElement('path', {
          class: `chart-area ${color}`,
          d: areaD
        });
        svg.appendChild(area);
      }

      // Line
      const line = Utils.createSVGElement('path', {
        class: `chart-line ${color} ${animate ? 'chart-line-animate' : ''}`,
        d: pathD
      });
      svg.appendChild(line);

      // Points
      if (showPoints) {
        seriesData.forEach((d, i) => {
          const point = Utils.createSVGElement('circle', {
            class: `chart-point ${color}`,
            cx: scaleX(d.x),
            cy: scaleY(d.y),
            r: 4,
            'data-index': i,
            'data-series': si,
            'data-value': d.y
          });
          svg.appendChild(point);
        });
      }
    });

    // Tooltip
    if (showTooltip) {
      const tooltip = Utils.createElement('div', { className: 'chart-tooltip' });
      container.appendChild(tooltip);

      svg.addEventListener('mousemove', (e) => {
        const point = e.target.closest('.chart-point');
        if (point) {
          const idx = parseInt(point.dataset.index);
          const seriesIdx = parseInt(point.dataset.series);
          const d = allSeries[seriesIdx].data[idx];
          
          tooltip.innerHTML = `
            <div class="tooltip-title">${d.label || Utils.formatDate(d.x)}</div>
            <div class="tooltip-row">
              <span class="tooltip-dot ${allSeries[seriesIdx].colorClass || colorClass}"></span>
              <span class="tooltip-label">${allSeries[seriesIdx].name || 'Value'}</span>
              <span class="tooltip-value">${Utils.formatNumber(d.y)}</span>
            </div>
          `;
          
          const rect = container.getBoundingClientRect();
          tooltip.style.left = `${e.clientX - rect.left + 10}px`;
          tooltip.style.top = `${e.clientY - rect.top - 10}px`;
          tooltip.classList.add('visible');
        } else {
          tooltip.classList.remove('visible');
        }
      });

      svg.addEventListener('mouseleave', () => {
        tooltip.classList.remove('visible');
      });
    }

    container.innerHTML = '';
    container.appendChild(svg);
    if (showTooltip) {
      const tooltip = Utils.createElement('div', { className: 'chart-tooltip' });
      container.appendChild(tooltip);
    }

    return { svg, update: (newData) => this.lineChart(container, { ...options, data: newData }) };
  },

  // ===== Bar Chart =====

  /**
   * Create a bar chart
   */
  barChart(container, options) {
    const {
      data = [],          // Array of { label, value, color? }
      width = null,
      height = null,
      horizontal = false,
      showValues = true,
      animate = true
    } = options;

    const rect = container.getBoundingClientRect();
    const w = width || rect.width || 400;
    const h = height || rect.height || 200;
    const padding = { top: 20, right: 20, bottom: 40, left: horizontal ? 100 : 50 };
    const chartW = w - padding.left - padding.right;
    const chartH = h - padding.top - padding.bottom;

    if (data.length === 0) {
      container.innerHTML = `<div class="chart-empty"><span class="chart-empty-icon">📊</span><span class="chart-empty-text">No data available</span></div>`;
      return;
    }

    const maxValue = Math.max(...data.map(d => d.value)) * 1.1 || 1;
    const barGap = 4;
    const barSize = horizontal 
      ? (chartH - barGap * (data.length - 1)) / data.length
      : (chartW - barGap * (data.length - 1)) / data.length;

    const svg = Utils.createSVGElement('svg', {
      class: 'chart-svg',
      viewBox: `0 0 ${w} ${h}`,
      preserveAspectRatio: 'xMidYMid meet'
    });

    // Grid
    const gridGroup = Utils.createSVGElement('g', { class: 'chart-grid' });
    const ticks = 5;
    for (let i = 0; i <= ticks; i++) {
      if (horizontal) {
        const x = padding.left + (chartW / ticks) * i;
        const line = Utils.createSVGElement('line', {
          x1: x, y1: padding.top,
          x2: x, y2: h - padding.bottom
        });
        gridGroup.appendChild(line);
      } else {
        const y = padding.top + (chartH / ticks) * i;
        const line = Utils.createSVGElement('line', {
          x1: padding.left, y1: y,
          x2: w - padding.right, y2: y
        });
        gridGroup.appendChild(line);
      }
    }
    svg.appendChild(gridGroup);

    // Bars
    data.forEach((d, i) => {
      const colorClass = d.color || 'primary';
      const ratio = d.value / maxValue;
      
      let barEl;
      if (horizontal) {
        const barLength = ratio * chartW;
        const y = padding.top + i * (barSize + barGap);
        barEl = Utils.createSVGElement('rect', {
          class: `chart-bar ${colorClass}`,
          x: padding.left,
          y,
          width: animate ? 0 : barLength,
          height: barSize,
          rx: 3
        });
        if (animate) {
          setTimeout(() => barEl.setAttribute('width', barLength), i * 50);
        }

        // Label
        const label = Utils.createSVGElement('text', {
          class: 'chart-axis',
          x: padding.left - 8,
          y: y + barSize / 2 + 4,
          'text-anchor': 'end'
        });
        label.textContent = d.label;
        svg.appendChild(label);

        // Value
        if (showValues) {
          const valText = Utils.createSVGElement('text', {
            class: 'chart-axis',
            x: padding.left + barLength + 8,
            y: y + barSize / 2 + 4,
            'text-anchor': 'start'
          });
          valText.textContent = Utils.formatNumber(d.value);
          svg.appendChild(valText);
        }
      } else {
        const barLength = ratio * chartH;
        const x = padding.left + i * (barSize + barGap);
        barEl = Utils.createSVGElement('rect', {
          class: `chart-bar ${colorClass}`,
          x,
          y: padding.top + chartH - (animate ? 0 : barLength),
          width: barSize,
          height: animate ? 0 : barLength,
          rx: 3
        });
        if (animate) {
          setTimeout(() => {
            barEl.setAttribute('height', barLength);
            barEl.setAttribute('y', padding.top + chartH - barLength);
          }, i * 50);
        }

        // Label
        const label = Utils.createSVGElement('text', {
          class: 'chart-axis',
          x: x + barSize / 2,
          y: h - padding.bottom + 20,
          'text-anchor': 'middle'
        });
        label.textContent = d.label;
        svg.appendChild(label);

        // Value
        if (showValues) {
          const valText = Utils.createSVGElement('text', {
            class: 'chart-axis',
            x: x + barSize / 2,
            y: padding.top + chartH - barLength - 8,
            'text-anchor': 'middle'
          });
          valText.textContent = Utils.formatNumber(d.value);
          svg.appendChild(valText);
        }
      }
      
      svg.appendChild(barEl);
    });

    container.innerHTML = '';
    container.appendChild(svg);

    return { svg };
  },

  // ===== Histogram =====

  /**
   * Create a histogram for distribution visualization
   */
  histogram(container, options) {
    const {
      data = [],          // Array of values
      bins = 10,
      width = null,
      height = null
    } = options;

    if (data.length === 0) {
      container.innerHTML = `<div class="chart-empty"><span class="chart-empty-icon">📊</span><span class="chart-empty-text">No data available</span></div>`;
      return;
    }

    // Create bins
    const min = Math.min(...data);
    const max = Math.max(...data);
    const binWidth = (max - min) / bins || 1;
    const histogram = Array(bins).fill(0);
    
    data.forEach(v => {
      const idx = Math.min(Math.floor((v - min) / binWidth), bins - 1);
      histogram[idx]++;
    });

    const barData = histogram.map((count, i) => ({
      label: `${Utils.formatDuration(min + i * binWidth)}`,
      value: count,
      color: 'primary'
    }));

    return this.barChart(container, { data: barData, ...options, showValues: false });
  },

  // ===== Donut Chart =====

  /**
   * Create a donut/pie chart
   */
  donutChart(container, options) {
    const {
      data = [],          // Array of { label, value, color }
      width = null,
      height = null,
      innerRadius = 0.6,  // 0 for pie, >0 for donut
      showLabels = true,
      centerLabel = null,
      centerSubLabel = null
    } = options;

    const rect = container.getBoundingClientRect();
    const w = width || rect.width || 200;
    const h = height || rect.height || 200;
    const cx = w / 2;
    const cy = h / 2;
    const radius = Math.min(w, h) / 2 - 10;
    const inner = radius * innerRadius;

    if (data.length === 0) {
      container.innerHTML = `<div class="chart-empty"><span class="chart-empty-icon">📊</span><span class="chart-empty-text">No data available</span></div>`;
      return;
    }

    const total = data.reduce((sum, d) => sum + d.value, 0);
    
    const svg = Utils.createSVGElement('svg', {
      class: 'chart-svg',
      viewBox: `0 0 ${w} ${h}`,
      preserveAspectRatio: 'xMidYMid meet'
    });

    // Draw slices
    let startAngle = -Math.PI / 2;
    const colorClasses = ['primary', 'success', 'error', 'warning', 'info'];
    
    data.forEach((d, i) => {
      const sliceAngle = (d.value / total) * 2 * Math.PI;
      const endAngle = startAngle + sliceAngle;
      const largeArc = sliceAngle > Math.PI ? 1 : 0;
      
      const x1 = cx + radius * Math.cos(startAngle);
      const y1 = cy + radius * Math.sin(startAngle);
      const x2 = cx + radius * Math.cos(endAngle);
      const y2 = cy + radius * Math.sin(endAngle);
      
      const ix1 = cx + inner * Math.cos(startAngle);
      const iy1 = cy + inner * Math.sin(startAngle);
      const ix2 = cx + inner * Math.cos(endAngle);
      const iy2 = cy + inner * Math.sin(endAngle);

      const pathD = inner > 0
        ? `M ${x1} ${y1} A ${radius} ${radius} 0 ${largeArc} 1 ${x2} ${y2} L ${ix2} ${iy2} A ${inner} ${inner} 0 ${largeArc} 0 ${ix1} ${iy1} Z`
        : `M ${cx} ${cy} L ${x1} ${y1} A ${radius} ${radius} 0 ${largeArc} 1 ${x2} ${y2} Z`;

      const color = d.color || colorClasses[i % colorClasses.length];
      const slice = Utils.createSVGElement('path', {
        class: `chart-slice`,
        d: pathD,
        fill: `var(--ctp-${color === 'primary' ? 'blue' : color === 'success' ? 'green' : color === 'error' ? 'red' : color === 'warning' ? 'yellow' : 'sapphire'})`
      });
      svg.appendChild(slice);

      startAngle = endAngle;
    });

    // Center labels
    if (centerLabel) {
      const label = Utils.createSVGElement('text', {
        class: 'chart-center-label',
        x: cx,
        y: cy
      });
      label.textContent = centerLabel;
      svg.appendChild(label);
    }

    if (centerSubLabel) {
      const sublabel = Utils.createSVGElement('text', {
        class: 'chart-center-sublabel',
        x: cx,
        y: cy + 20
      });
      sublabel.textContent = centerSubLabel;
      svg.appendChild(sublabel);
    }

    container.innerHTML = '';
    container.appendChild(svg);

    // Legend
    if (showLabels) {
      const legend = Utils.createElement('div', { className: 'chart-legend' });
      data.forEach((d, i) => {
        const color = d.color || colorClasses[i % colorClasses.length];
        const item = Utils.createElement('div', { className: 'legend-item' }, [
          Utils.createElement('span', { className: `legend-color ${color}` }),
          `${d.label} (${Utils.formatPercent((d.value / total) * 100)})`
        ]);
        legend.appendChild(item);
      });
      container.appendChild(legend);
    }

    return { svg };
  },

  // ===== Gauge Chart =====

  /**
   * Create a gauge chart for single value display
   */
  gaugeChart(container, options) {
    const {
      value = 0,
      max = 100,
      width = null,
      height = null,
      thresholds = { warning: 70, error: 90 },
      label = null,
      sublabel = null
    } = options;

    const rect = container.getBoundingClientRect();
    const w = width || rect.width || 150;
    const h = height || rect.height || 150;
    const cx = w / 2;
    const cy = h / 2 + 10;
    const radius = Math.min(w, h) / 2 - 15;

    const svg = Utils.createSVGElement('svg', {
      class: 'chart-svg',
      viewBox: `0 0 ${w} ${h}`,
      preserveAspectRatio: 'xMidYMid meet'
    });

    // Background arc
    const bgArc = Utils.createSVGElement('path', {
      class: 'gauge-background',
      d: describeArc(cx, cy, radius, -135, 135),
      fill: 'none'
    });
    svg.appendChild(bgArc);

    // Value arc
    const percent = Math.min(value / max, 1);
    const endAngle = -135 + percent * 270;
    let colorClass = 'success';
    if (value >= thresholds.error) colorClass = 'error';
    else if (value >= thresholds.warning) colorClass = 'warning';

    const valueArc = Utils.createSVGElement('path', {
      class: `gauge-value ${colorClass}`,
      d: describeArc(cx, cy, radius, -135, endAngle),
      fill: 'none'
    });
    svg.appendChild(valueArc);

    // Label
    const labelEl = Utils.createSVGElement('text', {
      class: 'gauge-label',
      x: cx,
      y: cy
    });
    labelEl.textContent = label || `${Math.round(value)}%`;
    svg.appendChild(labelEl);

    if (sublabel) {
      const sublabelEl = Utils.createSVGElement('text', {
        class: 'gauge-sublabel',
        x: cx,
        y: cy + 20
      });
      sublabelEl.textContent = sublabel;
      svg.appendChild(sublabelEl);
    }

    container.innerHTML = '';
    container.appendChild(svg);

    return { svg };

    function describeArc(x, y, r, startAngle, endAngle) {
      const start = polarToCartesian(x, y, r, endAngle);
      const end = polarToCartesian(x, y, r, startAngle);
      const largeArcFlag = endAngle - startAngle <= 180 ? 0 : 1;
      return `M ${start.x} ${start.y} A ${r} ${r} 0 ${largeArcFlag} 0 ${end.x} ${end.y}`;
    }

    function polarToCartesian(cx, cy, r, angle) {
      const rad = (angle - 90) * Math.PI / 180;
      return { x: cx + r * Math.cos(rad), y: cy + r * Math.sin(rad) };
    }
  },

  // ===== Sparkline =====

  /**
   * Create a mini sparkline chart
   */
  sparkline(container, options) {
    const {
      data = [],
      width = null,
      height = 30,
      showEndPoint = true
    } = options;

    const rect = container.getBoundingClientRect();
    const w = width || rect.width || 100;
    const h = height;

    if (data.length < 2) {
      container.innerHTML = '';
      return;
    }

    const min = Math.min(...data);
    const max = Math.max(...data);
    const range = max - min || 1;

    const points = data.map((v, i) => ({
      x: (i / (data.length - 1)) * w,
      y: h - ((v - min) / range) * (h - 4) - 2
    }));

    const svg = Utils.createSVGElement('svg', {
      class: 'chart-svg sparkline',
      viewBox: `0 0 ${w} ${h}`,
      preserveAspectRatio: 'none'
    });

    // Area
    const areaD = `M 0 ${h} ` + points.map(p => `L ${p.x} ${p.y}`).join(' ') + ` L ${w} ${h} Z`;
    const area = Utils.createSVGElement('path', {
      class: 'sparkline-area',
      d: areaD
    });
    svg.appendChild(area);

    // Line
    const lineD = points.map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x} ${p.y}`).join(' ');
    const line = Utils.createSVGElement('path', {
      class: 'sparkline-line',
      d: lineD
    });
    svg.appendChild(line);

    // End point
    if (showEndPoint) {
      const lastPoint = points[points.length - 1];
      const dot = Utils.createSVGElement('circle', {
        class: 'sparkline-point',
        cx: lastPoint.x,
        cy: lastPoint.y,
        r: 3
      });
      svg.appendChild(dot);
    }

    container.innerHTML = '';
    container.appendChild(svg);

    return { svg };
  },

  // ===== Stacked Bar Chart =====

  /**
   * Create stacked bar chart for composition analysis
   */
  stackedBarChart(container, options) {
    const {
      data = [],          // Array of { label, values: { key: value } }
      keys = [],          // Keys to stack
      colors = {},        // { key: colorClass }
      width = null,
      height = null
    } = options;

    const rect = container.getBoundingClientRect();
    const w = width || rect.width || 400;
    const h = height || rect.height || 200;
    const padding = { top: 20, right: 20, bottom: 40, left: 50 };
    const chartW = w - padding.left - padding.right;
    const chartH = h - padding.top - padding.bottom;

    if (data.length === 0) {
      container.innerHTML = `<div class="chart-empty"><span class="chart-empty-icon">📊</span><span class="chart-empty-text">No data available</span></div>`;
      return;
    }

    const totals = data.map(d => keys.reduce((sum, k) => sum + (d.values[k] || 0), 0));
    const maxTotal = Math.max(...totals) * 1.1 || 1;

    const barGap = 8;
    const barWidth = (chartW - barGap * (data.length - 1)) / data.length;

    const svg = Utils.createSVGElement('svg', {
      class: 'chart-svg',
      viewBox: `0 0 ${w} ${h}`,
      preserveAspectRatio: 'xMidYMid meet'
    });

    // Grid
    const gridGroup = Utils.createSVGElement('g', { class: 'chart-grid' });
    const ticks = 5;
    for (let i = 0; i <= ticks; i++) {
      const y = padding.top + (chartH / ticks) * i;
      const line = Utils.createSVGElement('line', {
        x1: padding.left, y1: y,
        x2: w - padding.right, y2: y
      });
      gridGroup.appendChild(line);
    }
    svg.appendChild(gridGroup);

    // Bars
    data.forEach((d, i) => {
      const x = padding.left + i * (barWidth + barGap);
      let y = padding.top + chartH;

      keys.forEach(key => {
        const value = d.values[key] || 0;
        const barH = (value / maxTotal) * chartH;
        y -= barH;

        const bar = Utils.createSVGElement('rect', {
          class: `chart-bar ${colors[key] || 'primary'}`,
          x, y,
          width: barWidth,
          height: barH,
          rx: 2
        });
        svg.appendChild(bar);
      });

      // Label
      const label = Utils.createSVGElement('text', {
        class: 'chart-axis',
        x: x + barWidth / 2,
        y: h - padding.bottom + 20,
        'text-anchor': 'middle'
      });
      label.textContent = d.label;
      svg.appendChild(label);
    });

    container.innerHTML = '';
    container.appendChild(svg);

    // Legend
    const legend = Utils.createElement('div', { className: 'chart-legend' });
    keys.forEach(key => {
      const item = Utils.createElement('div', { className: 'legend-item' }, [
        Utils.createElement('span', { className: `legend-color ${colors[key] || 'primary'}` }),
        key
      ]);
      legend.appendChild(item);
    });
    container.appendChild(legend);

    return { svg };
  }
};

// Export
window.Charts = Charts;
