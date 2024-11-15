classdef LifetimeTest_exported < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure                        matlab.ui.Figure
        withdownsamplefactorLabel       matlab.ui.control.Label
        DownsampleEditField             matlab.ui.control.NumericEditField
        SaverawdataCheckBox             matlab.ui.control.CheckBox
        DAQconnectionsAO0VoltagesignalPFI0LimittripLabel_2  matlab.ui.control.Label
        RawfilenameEditField            matlab.ui.control.EditField
        RawfilenameLabel                matlab.ui.control.Label
        PulseButton                     matlab.ui.control.Button
        Lamp_10                         matlab.ui.control.Lamp
        Lamp_9                          matlab.ui.control.Lamp
        Lamp_8                          matlab.ui.control.Lamp
        Lamp_7                          matlab.ui.control.Lamp
        Lamp_6                          matlab.ui.control.Lamp
        Lamp_5                          matlab.ui.control.Lamp
        Lamp_4                          matlab.ui.control.Lamp
        Lamp_3                          matlab.ui.control.Lamp
        Lamp_2                          matlab.ui.control.Lamp
        Lamp                            matlab.ui.control.Lamp
        CounterfilenameEditField        matlab.ui.control.EditField
        CounterfilenameLabel            matlab.ui.control.Label
        BrowseButton                    matlab.ui.control.Button
        SelectfilepathEditField         matlab.ui.control.EditField
        SelectfilepathEditFieldLabel    matlab.ui.control.Label
        StopButton                      matlab.ui.control.Button
        ContinueButton                  matlab.ui.control.Button
        CyclesEditField                 matlab.ui.control.NumericEditField
        CyclesEditFieldLabel            matlab.ui.control.Label
        HzLabel_2                       matlab.ui.control.Label
        HzLabel                         matlab.ui.control.Label
        kVLabel                         matlab.ui.control.Label
        GoButton                        matlab.ui.control.StateButton
        OutputsamplerateEditField       matlab.ui.control.NumericEditField
        OutputsamplerateEditFieldLabel  matlab.ui.control.Label
        FrequencyEditField              matlab.ui.control.NumericEditField
        FrequencyEditFieldLabel         matlab.ui.control.Label
        MaxVoltageEditField             matlab.ui.control.NumericEditField
        MaxVoltageEditFieldLabel        matlab.ui.control.Label
        ReversePolarityCheckBox         matlab.ui.control.CheckBox
        SignalTypeDropDown              matlab.ui.control.DropDown
        SignalTypeDropDownLabel         matlab.ui.control.Label
        DAQconnectionsAO0VoltagesignalPFI0LimittripLabel  matlab.ui.control.Label
        UIAxes                          matlab.ui.control.UIAxes
    end

    % Author: Zachary Yoder
    % Created: 22 February 2023
    % Last updated: 12 November 2024
    
    properties (Access = private)
        kV; % kVtrek/Vdaq
        d;
        devName;
        sampleRate;
        
        actuation;
        cycleCounter;
        breakdownCounter;
        
        downsampleFactor;
        counterFileID;
        rawFileID;
        
        pulseFlag;
        
        calibrationCounter;
        calibrationArr;
        currentOffset;
        currentMean;
        tolerance;
    end
    
    methods (Access = private)
        
        function buildPreview(app)
            singleCycle = buildSingleCycle(app);
            revPolarity = app.ReversePolarityCheckBox.Value;
            frequency = app.FrequencyEditField.Value;
            maxVoltage = app.MaxVoltageEditField.Value;
            
            previewTime = 4;
            previewSignal = buildFullSignal(app, singleCycle, ceil(frequency*previewTime), revPolarity);
            xPreviewSignal = linspace(0, length(previewSignal)/app.sampleRate, length(previewSignal));
            
            plot(app.UIAxes, xPreviewSignal, previewSignal*app.kV);
            app.UIAxes.YLim = [-maxVoltage - 1, maxVoltage + 1];
            app.UIAxes.XLim = [0, previewTime];
        end
        
        function singleSquare = buildSquare(~, sampleRate, maxVoltage, frequency)
            % Square wave signal, with actuation in the middle of the cycle
            cycleSamples = round(sampleRate/frequency); %samples/cycle
            startVoltage = round(cycleSamples/4);
            endVoltage = round(cycleSamples*3/4);
            singleSquare = zeros(cycleSamples, 1);
                
            singleSquare(startVoltage: endVoltage, 1) = maxVoltage;
        end
        
        function singleRamp = buildRamp(~, sampleRate, maxVoltage, frequency)
            % Ramped square signal, update for custom waveform
            cycleSamples = ceil(sampleRate/frequency);
            numMax = floor(cycleSamples/3);
            numRamp = ceil(cycleSamples/6);
            singleRamp = zeros(cycleSamples, 1);
            
            startRampUp = numMax + 1;
            startVoltage = startRampUp + numRamp;
            startRampDown = startVoltage + numMax;
            
            voltStep = maxVoltage/numRamp;
            
            for i = startRampUp - 1: startVoltage - 1
                singleRamp(i + 1, 1) = singleRamp(i, 1) + voltStep;
            end
                
            singleRamp(startVoltage: startRampDown - 1, 1) = maxVoltage;
        
            for i = startRampDown - 1: cycleSamples - 1
                singleRamp(i + 1, 1) = singleRamp(i, 1) - voltStep;
            end
        end
        
        function singleSine = buildSine(~, sampleRate, maxVoltage, frequency)
            cycleSamples = sampleRate/frequency;
            singleSine = (maxVoltage/2).*(sin(linspace(-pi/2, (3*pi)/2, cycleSamples))+1);
            singleSine = transpose(singleSine);
        end
        
        function singleTriangle = buildTriangle(~, sampleRate, maxVoltage, frequency)
            cycleSamples = sampleRate/frequency;
            singleTriangle = zeros(cycleSamples, 1);
            singleTriangle(1: cycleSamples/2) = linspace(0, maxVoltage, cycleSamples/2).';
            singleTriangle(cycleSamples/2 + 1: end) = linspace(maxVoltage, 0, cycleSamples/2);
        end
        
        function fullSignal = buildFullSignal(~, singleCycle, numCycles, revPolarity)
            % Combine single cycles into multi-cycle signal
            fullSignal = zeros(numCycles, 1);
            fullSignal(1: length(singleCycle), 1) = singleCycle;
            
            for i = 1:numCycles - 1
                j = i*length(singleCycle);
                if revPolarity
                    singleCycle = -singleCycle;
                end
                fullSignal(j + 1: j+length(singleCycle), 1) = singleCycle;
            end
        end
        
        function singleCycle = buildSingleCycle(app)
            signalType = app.SignalTypeDropDown.Value;
            maxVoltage = app.MaxVoltageEditField.Value/app.kV;
            frequency = app.FrequencyEditField.Value;
            
            if frequency == 0
                singleCycle = zeros(app.sampleRate, 1);
            else
                switch signalType
                    case 'Square'
                        singleCycle = buildSquare(app, app.sampleRate, maxVoltage, frequency);
                    case 'Ramped Square'
                        singleCycle = buildRamp(app, app.sampleRate, maxVoltage, frequency);
                    case 'Sine'
                        singleCycle = buildSine(app, app.sampleRate, maxVoltage, frequency);
                    case 'Triangle'
                        singleCycle = buildTriangle(app, app.sampleRate, maxVoltage, frequency);
                end
            end
        end
        
        function storeData(app, ~, ~)
            % This function is called every n = scansAvailableFcnCount data
            % points read by the DAQ           
            numScansAvailable = app.d.NumScansAvailable;
            if numScansAvailable == 0
                return;
            end
            
            % Read available data from DAQ
            scanData = read(app.d, numScansAvailable, "OutputFormat", "Matrix");           
            voltage = scanData(:, 1);
            current = scanData(:, 2);
            displacement = scanData(:, 3);

            % Write raw data to file
            if app.SaverawdataCheckBox.Value
                % Downsample data by specified factor
                voltageDownsampled = downsample(voltage.', app.downsampleFactor);
                currentDownsampled = downsample(current.', app.downsampleFactor);
                displacementDownsampled = downsample(displacement.', app.downsampleFactor);
                fprintf(app.rawFileID, '%.4f, %.4f, %.4f\n', [voltageDownsampled; currentDownsampled; displacementDownsampled]);
            end
            
            % Check for calibration
            if app.calibrationCounter < 2

                % Increment calibration counter
                app.calibrationCounter = app.calibrationCounter + 1;

                startIndex = (app.calibrationCounter - 1)*app.sampleRate + 1;
                endIndex = app.calibrationCounter*app.sampleRate;
                
                app.calibrationArr(startIndex: endIndex) = current;
                
                if app.calibrationCounter == 2
                    app.currentOffset = median(app.calibrationArr);
                    app.currentMean = mean(abs(app.calibrationArr - app.currentOffset));
                end
                
            elseif mean(abs(current - app.currentOffset)) > app.tolerance*app.currentMean
                % Breakdown has occurred
                
                % Stop actuation
                stop(app.d);
                write(app.d, 0);
                
                % Write number of cycles to file
                if app.pulseFlag == 0
                    app.breakdownCounter = app.breakdownCounter + 1;
                    fprintf(app.counterFileID, '%.4f, %.4f\n', [app.breakdownCounter, app.cycleCounter]);
                end
                
                % Display what happened
                app.GoButton.Text = 'Breakdown';
                app.GoButton.Enable = 0;
                app.GoButton.BackgroundColor = [0.93, 0.69, 0.13];
                
                app.Lamp.Color = 'red';
                app.Lamp_2.Color = 'red';
                app.Lamp_3.Color = 'red';
                app.Lamp_4.Color = 'red';
                app.Lamp_5.Color = 'red';
                app.Lamp_6.Color = 'red';
                app.Lamp_7.Color = 'red';
                app.Lamp_8.Color = 'red';
                app.Lamp_9.Color = 'red';
                app.Lamp_10.Color = 'red';

                % User can decide what to do next
                % Enable these buttons and handle behavior in callback
                app.ContinueButton.Visible = 1;
                app.StopButton.Visible = 1;
                app.PulseButton.Visible = 1;
                
            else
                % No breakdown detected
                app.cycleCounter = app.cycleCounter + app.FrequencyEditField.Value;
                app.CyclesEditField.Value = app.cycleCounter;
            end
        end
    end

    % Callbacks that handle component events
    methods (Access = private)

        % Code that executes after component creation
        function startupFcn(app)
            % Voltage constant
            app.kV = 2; % [kV/V]
                
            %app.d.ErrorOccurredFcn = @(src, event) errorFcn(app, src, event);

            % Select and connect to DAQ
            available_daqs = daqlist;
            if isempty(available_daqs)
                uiwait(msgbox("No DAQ selected, preview mode only", "Error", 'modal'));
                app.GoButton.Enable = 0;
            else
                [idx, ~] = listdlg('PromptString', 'Select a device.', ...
                    'SelectionMode', 'single', 'ListString', available_daqs.Model);

                % Set up DAQ
                app.d = daq("ni");
                app.sampleRate = app.OutputsamplerateEditField.Value;
                app.devName = available_daqs.DeviceID(idx);
                app.d.Rate = app.sampleRate;

                % Set up callback functions
                app.d.ScansAvailableFcn = @(src, event) storeData(app, src, event);
                    % call storeData fcn when scans are available
                app.d.ScansAvailableFcnCount = app.sampleRate;
                    % call storeData every cycle
    
                % Add input, output channels
                addoutput(app.d, app.devName, "ao0", "Voltage");
                    % TREK voltage output
                addinput(app.d, app.devName, "ai0", "Voltage");
                    % TREK voltage monitor
                addinput(app.d, app.devName, "ai1", "Voltage");
                    % TREK current monitor
                addinput(app.d, app.devName, "ai2", "Voltage");
                    % Laser displacement sensor
            
                % Set up app
                app.ContinueButton.Visible = 0;
                app.StopButton.Visible = 0;
                app.PulseButton.Visible = 0;
                
                app.pulseFlag = 0;
                app.currentOffset = 0;
                app.currentMean = 0;
                app.downsampleFactor = app.DownsampleEditField.Value;
                
                % Breakdown detection tolerance
                app.tolerance = 2;
                    % Program measures the mean current over the first few cycles
                    % Then, if the measured current exceeds currentMean*tolerance, the program assumes breakdown
                    % (higher value = less sensitive, lower value = more sensitive)
                
                % Build signal preview
                buildPreview(app);
            end
        end

        % Value changed function: GoButton
        function GoButtonValueChanged(app, event)
            if app.GoButton.Value
                % Begin test
                app.GoButton.Text = "Stop";
                app.GoButton.BackgroundColor = [0.85, 0.33, 0.10];
                
                % Set up file writing
                app.counterFileID = fopen(fullfile(app.SelectfilepathEditField.Value, app.CounterfilenameEditField.Value), 'w');
                if app.SaverawdataCheckBox.Value
                    app.rawFileID = fopen(fullfile(app.SelectfilepathEditField.Value, app.RawfilenameEditField.Value), 'w');
                end
                
                % Build actuation signal
                numCycles = 2;
                voltageSignal = buildFullSignal(app, buildSingleCycle(app), numCycles, app.ReversePolarityCheckBox.Value);

                % Ensure we are preloading enough data
                while length(voltageSignal) < round(app.sampleRate/2)
                    numCycles = numCycles + 2;
                    voltageSignal = buildFullSignal(app, buildSingleCycle(app), numCycles, app.ReversePolarityCheckBox.Value);
                end
                
                app.actuation = voltageSignal;
                
                app.cycleCounter = 0;
                app.CyclesEditField.Value = app.cycleCounter;
                app.breakdownCounter = 0;
                app.calibrationCounter = 0;
                app.calibrationArr = zeros(2*app.sampleRate, 1);
                
                preload(app.d, voltageSignal);
                start(app.d, "RepeatOutput");
            else
                % Write last cycles
                app.breakdownCounter = app.breakdownCounter + 1;
                fprintf(app.counterFileID, '%.4f, %.4f\n', [app.breakdownCounter, app.cycleCounter]);
                % Close files
                fclose(app.counterFileID);
                if app.SaverawdataCheckBox.Value
                    fclose(app.rawFileID);
                end
                stop(app.d);
                flush(app.d);
                write(app.d, 0);
                
                % Reset app
                app.ContinueButton.Visible = 0;
                app.StopButton.Visible = 0;
                app.PulseButton.Visible = 0;
                
                app.GoButton.Text = "Go";
                app.GoButton.Enable = 1;
                app.GoButton.BackgroundColor = [0.00, 0.45, 0.74];
            end
        end

        % Value changed function: MaxVoltageEditField
        function MaxVoltageEditFieldValueChanged(app, event)
            buildPreview(app);
        end

        % Value changed function: FrequencyEditField
        function FrequencyEditFieldValueChanged(app, event)
            buildPreview(app);
        end

        % Value changed function: SignalTypeDropDown
        function SignalTypeDropDownValueChanged(app, event)
            buildPreview(app);
        end

        % Value changed function: ReversePolarityCheckBox
        function ReversePolarityCheckBoxValueChanged(app, event)
            buildPreview(app);
        end

        % Value changed function: OutputsamplerateEditField
        function OutputsamplerateEditFieldValueChanged(app, event)
            app.sampleRate = app.OutputsamplerateEditField.Value;
            app.d.Rate = app.sampleRate;
            app.d.ScansAvailableFcnCount = app.sampleRate;
        end

        % Button pushed function: ContinueButton
        function ContinueButtonPushed(app, event)
            % start cycling again, basically gobutton
            
            app.pulseFlag = 0;
            flush(app.d);
            
            preload(app.d, app.actuation);
            start(app.d, "RepeatOutput");
            
            app.Lamp.Color = 'white';
            app.Lamp_2.Color = 'white';
            app.Lamp_3.Color = 'white';
            app.Lamp_4.Color = 'white';
            app.Lamp_5.Color = 'white';
            app.Lamp_6.Color = 'white';
            app.Lamp_7.Color = 'white';
            app.Lamp_8.Color = 'white';
            app.Lamp_9.Color = 'white';
            app.Lamp_10.Color = 'white';
        
            app.ContinueButton.Visible = 0;
            app.StopButton.Visible = 0;
            app.PulseButton.Visible = 0;
            
            app.GoButton.Text = 'Stop';
            app.GoButton.Enable = 1;
            app.GoButton.BackgroundColor = [0.00, 0.45, 0.74];
        end

        % Button pushed function: StopButton
        function StopButtonPushed(app, event)
            % Reset UI
            app.pulseFlag = 0;
            
            app.Lamp.Color = 'white';
            app.Lamp_2.Color = 'white';
            app.Lamp_3.Color = 'white';
            app.Lamp_4.Color = 'white';
            app.Lamp_5.Color = 'white';
            app.Lamp_6.Color = 'white';
            app.Lamp_7.Color = 'white';
            app.Lamp_8.Color = 'white';
            app.Lamp_9.Color = 'white';
            app.Lamp_10.Color = 'white';
            
            % Call GoButtonValueChanged to end program and reset app
            app.GoButton.Value = 0;
            app.GoButtonValueChanged;
        end

        % Button pushed function: BrowseButton
        function BrowseButtonPushed(app, event)
                filepath = uigetdir;
            try
                app.SelectfilepathEditField.Value = filepath;
            catch
                uiwait(msgbox("No filepath selected", "Warning", 'warn', 'modal'));
                app.SelectfilepathEditField.Value = "";
            end
        end

        % Button pushed function: PulseButton
        function PulseButtonPushed(app, event)
            app.pulseFlag = 1;
            flush(app.d);
            preload(app.d, app.actuation);
            start(app.d);
            app.cycleCounter = app.cycleCounter + app.FrequencyEditField.Value;
            app.CyclesEditField.Value = app.cycleCounter;
        end

        % Value changed function: SaverawdataCheckBox
        function SaverawdataCheckBoxValueChanged(app, event)
            app.RawfilenameEditField.Enable = app.SaverawdataCheckBox.Value;
            app.DownsampleEditField.Enable = app.SaverawdataCheckBox.Value;
        end

        % Value changed function: DownsampleEditField
        function DownsampleEditFieldValueChanged(app, event)
            app.downsampleFactor = app.DownsampleEditField.Value;    
        end
    end

    % Component initialization
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)

            % Create UIFigure and hide until all components are created
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 641 536];
            app.UIFigure.Name = 'MATLAB App';

            % Create UIAxes
            app.UIAxes = uiaxes(app.UIFigure);
            title(app.UIAxes, 'Voltage Signal Preview')
            xlabel(app.UIAxes, 'Time (s)')
            ylabel(app.UIAxes, 'Voltage (kV)')
            app.UIAxes.PlotBoxAspectRatio = [1.45813953488372 1 1];
            app.UIAxes.FontWeight = 'bold';
            app.UIAxes.XTickLabelRotation = 0;
            app.UIAxes.YTickLabelRotation = 0;
            app.UIAxes.ZTickLabelRotation = 0;
            app.UIAxes.Box = 'on';
            app.UIAxes.Position = [6 257 364 271];

            % Create DAQconnectionsAO0VoltagesignalPFI0LimittripLabel
            app.DAQconnectionsAO0VoltagesignalPFI0LimittripLabel = uilabel(app.UIFigure);
            app.DAQconnectionsAO0VoltagesignalPFI0LimittripLabel.FontWeight = 'bold';
            app.DAQconnectionsAO0VoltagesignalPFI0LimittripLabel.Position = [374 18 186 59];
            app.DAQconnectionsAO0VoltagesignalPFI0LimittripLabel.Text = {'AO0: TREK voltage input'; 'AI0: TREK voltage monitor'; 'AI1: TREK current monitor'; 'AI2: Laser displacement sensor'};

            % Create SignalTypeDropDownLabel
            app.SignalTypeDropDownLabel = uilabel(app.UIFigure);
            app.SignalTypeDropDownLabel.HorizontalAlignment = 'right';
            app.SignalTypeDropDownLabel.Position = [50 194 67 22];
            app.SignalTypeDropDownLabel.Text = 'Signal Type';

            % Create SignalTypeDropDown
            app.SignalTypeDropDown = uidropdown(app.UIFigure);
            app.SignalTypeDropDown.Items = {'Square', 'Ramped Square', 'Sine', 'Triangle'};
            app.SignalTypeDropDown.ValueChangedFcn = createCallbackFcn(app, @SignalTypeDropDownValueChanged, true);
            app.SignalTypeDropDown.Position = [132 194 121 22];
            app.SignalTypeDropDown.Value = 'Sine';

            % Create ReversePolarityCheckBox
            app.ReversePolarityCheckBox = uicheckbox(app.UIFigure);
            app.ReversePolarityCheckBox.ValueChangedFcn = createCallbackFcn(app, @ReversePolarityCheckBoxValueChanged, true);
            app.ReversePolarityCheckBox.Text = 'Reverse Polarity';
            app.ReversePolarityCheckBox.Position = [97 63 109 22];
            app.ReversePolarityCheckBox.Value = true;

            % Create MaxVoltageEditFieldLabel
            app.MaxVoltageEditFieldLabel = uilabel(app.UIFigure);
            app.MaxVoltageEditFieldLabel.HorizontalAlignment = 'right';
            app.MaxVoltageEditFieldLabel.Position = [64 126 72 22];
            app.MaxVoltageEditFieldLabel.Text = 'Max Voltage';

            % Create MaxVoltageEditField
            app.MaxVoltageEditField = uieditfield(app.UIFigure, 'numeric');
            app.MaxVoltageEditField.Limits = [0 20];
            app.MaxVoltageEditField.ValueChangedFcn = createCallbackFcn(app, @MaxVoltageEditFieldValueChanged, true);
            app.MaxVoltageEditField.Position = [151 126 45 22];
            app.MaxVoltageEditField.Value = 6;

            % Create FrequencyEditFieldLabel
            app.FrequencyEditFieldLabel = uilabel(app.UIFigure);
            app.FrequencyEditFieldLabel.HorizontalAlignment = 'right';
            app.FrequencyEditFieldLabel.Position = [64 96 62 22];
            app.FrequencyEditFieldLabel.Text = 'Frequency';

            % Create FrequencyEditField
            app.FrequencyEditField = uieditfield(app.UIFigure, 'numeric');
            app.FrequencyEditField.Limits = [0 Inf];
            app.FrequencyEditField.ValueChangedFcn = createCallbackFcn(app, @FrequencyEditFieldValueChanged, true);
            app.FrequencyEditField.Position = [151 96 45 22];
            app.FrequencyEditField.Value = 5;

            % Create OutputsamplerateEditFieldLabel
            app.OutputsamplerateEditFieldLabel = uilabel(app.UIFigure);
            app.OutputsamplerateEditFieldLabel.HorizontalAlignment = 'right';
            app.OutputsamplerateEditFieldLabel.Position = [30 157 108 22];
            app.OutputsamplerateEditFieldLabel.Text = 'Output sample rate';

            % Create OutputsamplerateEditField
            app.OutputsamplerateEditField = uieditfield(app.UIFigure, 'numeric');
            app.OutputsamplerateEditField.Limits = [0 Inf];
            app.OutputsamplerateEditField.RoundFractionalValues = 'on';
            app.OutputsamplerateEditField.ValueChangedFcn = createCallbackFcn(app, @OutputsamplerateEditFieldValueChanged, true);
            app.OutputsamplerateEditField.Position = [151 157 45 22];
            app.OutputsamplerateEditField.Value = 10000;

            % Create GoButton
            app.GoButton = uibutton(app.UIFigure, 'state');
            app.GoButton.ValueChangedFcn = createCallbackFcn(app, @GoButtonValueChanged, true);
            app.GoButton.Text = 'Go';
            app.GoButton.BackgroundColor = [0 0.451 0.7412];
            app.GoButton.FontSize = 24;
            app.GoButton.FontWeight = 'bold';
            app.GoButton.Position = [425 359 166 66];

            % Create kVLabel
            app.kVLabel = uilabel(app.UIFigure);
            app.kVLabel.Position = [205 126 25 22];
            app.kVLabel.Text = 'kV';

            % Create HzLabel
            app.HzLabel = uilabel(app.UIFigure);
            app.HzLabel.Position = [205 96 25 22];
            app.HzLabel.Text = 'Hz';

            % Create HzLabel_2
            app.HzLabel_2 = uilabel(app.UIFigure);
            app.HzLabel_2.Position = [205 157 25 22];
            app.HzLabel_2.Text = 'Hz';

            % Create CyclesEditFieldLabel
            app.CyclesEditFieldLabel = uilabel(app.UIFigure);
            app.CyclesEditFieldLabel.HorizontalAlignment = 'right';
            app.CyclesEditFieldLabel.FontSize = 18;
            app.CyclesEditFieldLabel.FontWeight = 'bold';
            app.CyclesEditFieldLabel.Position = [377 485 64 22];
            app.CyclesEditFieldLabel.Text = 'Cycles';

            % Create CyclesEditField
            app.CyclesEditField = uieditfield(app.UIFigure, 'numeric');
            app.CyclesEditField.Editable = 'off';
            app.CyclesEditField.FontSize = 18;
            app.CyclesEditField.FontWeight = 'bold';
            app.CyclesEditField.Position = [452 480 171 32];

            % Create ContinueButton
            app.ContinueButton = uibutton(app.UIFigure, 'push');
            app.ContinueButton.ButtonPushedFcn = createCallbackFcn(app, @ContinueButtonPushed, true);
            app.ContinueButton.BackgroundColor = [0.4667 0.6745 0.1882];
            app.ContinueButton.Position = [415 268 64 38];
            app.ContinueButton.Text = 'Continue';

            % Create StopButton
            app.StopButton = uibutton(app.UIFigure, 'push');
            app.StopButton.ButtonPushedFcn = createCallbackFcn(app, @StopButtonPushed, true);
            app.StopButton.BackgroundColor = [0.851 0.3255 0.098];
            app.StopButton.Position = [483 268 59 38];
            app.StopButton.Text = 'Stop';

            % Create SelectfilepathEditFieldLabel
            app.SelectfilepathEditFieldLabel = uilabel(app.UIFigure);
            app.SelectfilepathEditFieldLabel.HorizontalAlignment = 'right';
            app.SelectfilepathEditFieldLabel.Position = [406 225 101 22];
            app.SelectfilepathEditFieldLabel.Text = 'Select file path:';

            % Create SelectfilepathEditField
            app.SelectfilepathEditField = uieditfield(app.UIFigure, 'text');
            app.SelectfilepathEditField.Position = [301 195 322 22];

            % Create BrowseButton
            app.BrowseButton = uibutton(app.UIFigure, 'push');
            app.BrowseButton.ButtonPushedFcn = createCallbackFcn(app, @BrowseButtonPushed, true);
            app.BrowseButton.Position = [523 225 100 22];
            app.BrowseButton.Text = 'Browse';

            % Create CounterfilenameLabel
            app.CounterfilenameLabel = uilabel(app.UIFigure);
            app.CounterfilenameLabel.HorizontalAlignment = 'right';
            app.CounterfilenameLabel.Position = [291 162 100 22];
            app.CounterfilenameLabel.Text = 'Counter filename:';

            % Create CounterfilenameEditField
            app.CounterfilenameEditField = uieditfield(app.UIFigure, 'text');
            app.CounterfilenameEditField.Position = [398 162 224 22];
            app.CounterfilenameEditField.Value = 'testCounter.txt';

            % Create Lamp
            app.Lamp = uilamp(app.UIFigure);
            app.Lamp.Position = [425 437 20 20];
            app.Lamp.Color = [1 1 1];

            % Create Lamp_2
            app.Lamp_2 = uilamp(app.UIFigure);
            app.Lamp_2.Position = [464 437 20 20];
            app.Lamp_2.Color = [1 1 1];

            % Create Lamp_3
            app.Lamp_3 = uilamp(app.UIFigure);
            app.Lamp_3.Position = [500 437 20 20];
            app.Lamp_3.Color = [1 1 1];

            % Create Lamp_4
            app.Lamp_4 = uilamp(app.UIFigure);
            app.Lamp_4.Position = [536 437 20 20];
            app.Lamp_4.Color = [1 1 1];

            % Create Lamp_5
            app.Lamp_5 = uilamp(app.UIFigure);
            app.Lamp_5.Position = [571 437 20 20];
            app.Lamp_5.Color = [1 1 1];

            % Create Lamp_6
            app.Lamp_6 = uilamp(app.UIFigure);
            app.Lamp_6.Position = [425 328 20 20];
            app.Lamp_6.Color = [1 1 1];

            % Create Lamp_7
            app.Lamp_7 = uilamp(app.UIFigure);
            app.Lamp_7.Position = [464 328 20 20];
            app.Lamp_7.Color = [1 1 1];

            % Create Lamp_8
            app.Lamp_8 = uilamp(app.UIFigure);
            app.Lamp_8.Position = [500 328 20 20];
            app.Lamp_8.Color = [1 1 1];

            % Create Lamp_9
            app.Lamp_9 = uilamp(app.UIFigure);
            app.Lamp_9.Position = [536 328 20 20];
            app.Lamp_9.Color = [1 1 1];

            % Create Lamp_10
            app.Lamp_10 = uilamp(app.UIFigure);
            app.Lamp_10.Position = [571 328 20 20];
            app.Lamp_10.Color = [1 1 1];

            % Create PulseButton
            app.PulseButton = uibutton(app.UIFigure, 'push');
            app.PulseButton.ButtonPushedFcn = createCallbackFcn(app, @PulseButtonPushed, true);
            app.PulseButton.BackgroundColor = [0.9294 0.6941 0.1255];
            app.PulseButton.Position = [546 268 59 38];
            app.PulseButton.Text = 'Pulse';

            % Create RawfilenameLabel
            app.RawfilenameLabel = uilabel(app.UIFigure);
            app.RawfilenameLabel.HorizontalAlignment = 'right';
            app.RawfilenameLabel.Position = [293 131 82 22];
            app.RawfilenameLabel.Text = 'Raw filename:';

            % Create RawfilenameEditField
            app.RawfilenameEditField = uieditfield(app.UIFigure, 'text');
            app.RawfilenameEditField.Enable = 'off';
            app.RawfilenameEditField.Position = [398 131 224 22];
            app.RawfilenameEditField.Value = 'testRaw.txt';

            % Create DAQconnectionsAO0VoltagesignalPFI0LimittripLabel_2
            app.DAQconnectionsAO0VoltagesignalPFI0LimittripLabel_2 = uilabel(app.UIFigure);
            app.DAQconnectionsAO0VoltagesignalPFI0LimittripLabel_2.FontWeight = 'bold';
            app.DAQconnectionsAO0VoltagesignalPFI0LimittripLabel_2.Position = [262 36 110 22];
            app.DAQconnectionsAO0VoltagesignalPFI0LimittripLabel_2.Text = 'DAQ connections:';

            % Create SaverawdataCheckBox
            app.SaverawdataCheckBox = uicheckbox(app.UIFigure);
            app.SaverawdataCheckBox.ValueChangedFcn = createCallbackFcn(app, @SaverawdataCheckBoxValueChanged, true);
            app.SaverawdataCheckBox.Text = 'Save raw data';
            app.SaverawdataCheckBox.Position = [326 96 99 22];

            % Create DownsampleEditField
            app.DownsampleEditField = uieditfield(app.UIFigure, 'numeric');
            app.DownsampleEditField.Limits = [1 1000];
            app.DownsampleEditField.ValueChangedFcn = createCallbackFcn(app, @DownsampleEditFieldValueChanged, true);
            app.DownsampleEditField.Enable = 'off';
            app.DownsampleEditField.Position = [564 96 59 22];
            app.DownsampleEditField.Value = 100;

            % Create withdownsamplefactorLabel
            app.withdownsamplefactorLabel = uilabel(app.UIFigure);
            app.withdownsamplefactorLabel.Position = [424 96 134 22];
            app.withdownsamplefactorLabel.Text = 'with downsample factor:';

            % Show the figure after all components are created
            app.UIFigure.Visible = 'on';
        end
    end

    % App creation and deletion
    methods (Access = public)

        % Construct app
        function app = LifetimeTest_exported

            % Create UIFigure and components
            createComponents(app)

            % Register the app with App Designer
            registerApp(app, app.UIFigure)

            % Execute the startup function
            runStartupFcn(app, @startupFcn)

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)

            % Delete UIFigure when app is deleted
            delete(app.UIFigure)
        end
    end
end