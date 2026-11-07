import React from 'react';
import { RadiogramBlank } from './RadiogramBlank';
import { visibleDecodedCodes } from './radiogramView';

export function Task5Exchange({ step, variant, recovery, codeMessage, decodedReceivedCodes, correctionNotice, status, response, currentGroup }) {
  const outgoingGram = step?.direction === 'transmit' && step.bodyGroups > 0 ? variant.radiograms.find(gram => gram.id === step.radiogramID) : null;
  const outgoing = recovery ? response : step?.direction === 'transmit' && (step.bodyGroups || step.kind === 'signal') ? step.expectedMessages[0] : codeMessage?.text;
  const receivedMeanings = visibleDecodedCodes(step, decodedReceivedCodes);
  return <>
    {outgoingGram ? <RadiogramBlank gram={outgoingGram} recovery={recovery} response={response} currentGroup={currentGroup} /> : outgoing && <pre className="task5-wire" aria-label="Бланк передачи">{outgoing}</pre>}
    {!outgoingGram && codeMessage?.groups.length > 0 && <p className="task5-notice">{codeMessage.groups.map(group => `${group.code} — ${group.meaning}`).join(' · ')}</p>}
    {receivedMeanings.length > 0 && <section aria-label="Расшифровка принятых кодов"><p className="task5-notice">Принятые коды</p>{receivedMeanings.map((entry, index) => <p key={`${entry.stepID}-${index}`}>{entry.groups.map(group => `${group.code} — ${group.meaning}`).join(' · ')}</p>)}</section>}
    {correctionNotice && status !== 'playing' && <p className="task5-notice" role="status">{correctionNotice}</p>}
  </>;
}
