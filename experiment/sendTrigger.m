function sendTrigger(trigVal, refrate, MEG, trackeye)
    if MEG
        triggerPulse = [1 0] .* trigVal;
        Datapixx('StopDoutSchedule');
        Datapixx('WriteDoutBuffer', triggerPulse);
        Datapixx('SetDoutSchedule', 1.0/refrate, 1000, 2);
        Datapixx('StartDoutSchedule');
        % Note: RegWrVideoSync must be called in the main frame loop, not here
    end
    if trackeye
        Eyelink('Message', sprintf('TRIGGER %d', trigVal));
    end
end