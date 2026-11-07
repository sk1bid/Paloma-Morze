import React, { useLayoutEffect, useRef, useState } from 'react';
import { radiogramRows, radiogramHeaderFields, requestedRadiogramGroup } from './radiogramView';

export function RadiogramBlank({ gram, recovery, response, currentGroup }) {
  const requested = requestedRadiogramGroup(recovery);
  const headerRequested = recovery?.request === 'РПТ ПБЛ К';
  const root = useRef(null);
  const [fontSize, setFontSize] = useState(20);
  useLayoutEffect(() => {
    const element = root.current;
    const workspace = element?.closest('.task5-workspace');
    if (!workspace) return;
    const fit = () => {
      const gap = Number.parseFloat(getComputedStyle(workspace).gap) || 0;
      const other = [...workspace.children].filter(child => child !== element).reduce((height, child) => {
        const style = getComputedStyle(child);
        return height + child.getBoundingClientRect().height + (Number.parseFloat(style.marginTop) || 0) + (Number.parseFloat(style.marginBottom) || 0) + gap;
      }, 0);
      const request = element.querySelector('.task5-radiogram-request');
      const reserved = request ? Number.parseFloat(getComputedStyle(request).marginTop) || 0 : 0;
      const rows = Math.ceil(gram.groups.length / 5);
      const lines = rows + 3 + (request?.children.length || 0);
      const vertical = (target, properties) => {
        if (!target) return 0;
        const style = getComputedStyle(target);
        return properties.reduce((total, property) => total + (Number.parseFloat(style[property]) || 0), 0);
      };
      const heading = element.querySelector('.task5-radiogram-heading');
      const address = element.querySelector('[aria-label="Категория и адрес"]');
      const footer = element.querySelector('[aria-label="Конец радиограммы"]');
      const paper = element.querySelector('.task5-radiogram-paper');
      const fixed = vertical(paper, ['paddingTop', 'paddingBottom', 'borderTopWidth', 'borderBottomWidth'])
        + (element.querySelector('.task5-radiogram-caption')?.getBoundingClientRect().height || 0)
        + vertical(heading, ['borderBottomWidth'])
        + vertical(element.querySelector('.task5-radiogram-field'), ['paddingTop', 'paddingBottom'])
        + vertical(address, ['paddingTop', 'paddingBottom', 'borderBottomWidth'])
        + vertical(footer, ['paddingTop', 'paddingBottom'])
        + vertical(element.querySelector('td'), ['borderTopWidth']) * (rows + 1);
      const available = workspace.clientHeight - other - reserved - fixed - 2;
      setFontSize(Math.max(15, Math.min(20, Math.floor(available / lines))));
      if (workspace.scrollHeight <= workspace.clientHeight + 1) { workspace.scrollTop = 0; return; }
      const group = requested || currentGroup;
      const target = headerRequested || !group ? element.querySelector('[aria-label="Заголовок"]')
        : group > gram.groups.length ? element.querySelector('[aria-label="Конец радиограммы"]')
          : element.querySelector(`[data-group="${group}"]`);
      if (!target) return;
      const bounds = workspace.getBoundingClientRect(), position = target.getBoundingClientRect();
      if (position.top < bounds.top) workspace.scrollTop += position.top - bounds.top;
      else if (position.bottom > bounds.bottom) workspace.scrollTop += position.bottom - bounds.bottom;
    };
    fit();
    const observer = new ResizeObserver(fit);
    observer.observe(workspace);
    for (const child of workspace.children) observer.observe(child);
    return () => observer.disconnect();
  }, [gram.groups.length, requested, headerRequested, currentGroup, response]);
  return (
    <section className="task5-radiogram task5-wire" aria-label="Бланк передачи" ref={root} style={{ '--task5-gram-font-size': `${fontSize}px` }}>
      <div className="task5-radiogram-paper">
        <div className={`task5-radiogram-heading ${headerRequested ? 'requested' : ''}`} aria-label="Заголовок">
          {radiogramHeaderFields(gram).map(field => <div className="task5-radiogram-field" key={field.label}>
            <span className="task5-radiogram-caption">{field.label}</span>
            <span className="task5-radiogram-value">{field.value}</span>
          </div>)}
        </div>
        <div className={`task5-radiogram-line task5-radiogram-address ${headerRequested ? 'requested' : ''}`} aria-label="Категория и адрес"><span className="task5-radiogram-caption">Адрес</span><span>{gram.urgencyCode} {gram.address} =</span></div>
        <table className="task5-radiogram-body" aria-label="Текст радиограммы">
          <tbody>
            {radiogramRows(gram.groups).map((row, rowIndex) => (
              <tr key={rowIndex}>
                {row.map((group, column) => {
                  const number = rowIndex * 5 + column + 1;
                  return <td key={number} data-group={number} className={requested === number ? 'requested' : ''} aria-label={`Группа ${number}${requested === number ? ', запрошен повтор' : ''}`}>{group}</td>;
                })}
              </tr>
            ))}
          </tbody>
        </table>
        <div className="task5-radiogram-line" aria-label="Конец радиограммы">К</div>
      </div>
      {recovery && <div className="task5-radiogram-request" aria-label="Запрошенный ответ">
        <p className="task5-notice">{recovery.request}</p>
        {recovery.request !== 'РПТ АЛ К' && <p>{response}</p>}
      </div>}
    </section>
  );
}
