% eprload  Load experimental EPR data 
%
%   y = eprload(FileName)
%   [x,y] = eprload(FileName)
%   [x,y,Pars] = eprload(FileName)
%   [x,y,Pars,FileN] = eprload(FileName)
%   ... = eprload(FileName,Scaling)
%   ... = eprload
%
%   Read spectral data from a file specified in the string
%   'FileName' into the arrays x (abscissa) and y (ordinate).
%   The structure Pars contains entries from the parameter
%   file, if present.
%
%   All strings in the parameter structure containing numbers
%   are converted to numbers for easier use.
%
%   If FileName is a directory, a file browser is
%   displayed. If FileName is omitted, the current
%   directory is used as default. eprload returns the
%   name of the loaded file (including its path) as
%   fourth parameter FileN.
%
%   For DSC/DTA data, x contains the vector or
%   the vectors specifying the abscissa or abscissae of the
%   spectral data array, i.e. magnetic field range
%   for cw EPR, RF range for ENDOR and time delays
%   for pulse EPR. Units are those specified in
%   the parameter file. See the fields XPTS, XMIN, XWID
%   etc. in the Pars structure.
%
%   Supported formats are identified via the extension
%   in 'FileName'. Extensions:
%
%     Bruker BES3T:        .DTA, .DSC
%     Bruker ESP, WinEPR:  .spc, .par
%     SpecMan:             .d01, .exp
%     Magnettech:          .spe (binary), .xml (xml)
%     Active Spectrum:     .ESR
%     Adani:               .dat
%
%     MAGRES:              .PLT
%     qese, tryscore:      .eco
%     Varian:              .spk, .ref
%     ESE:                 .d00, .exp
%
%     For reading general ASCII formats, use textread(...)
%
%   'Scaling' tells eprload to scale the data (works only for Bruker files):
%
%      'n':   divide by number of scans
%      'P':   divide by square root of microwave power in mW
%      'G':   divide by receiver gain
%      'T':   multiply by temperature in kelvin
%      'c':   divide by conversion/sampling time in milliseconds

function varargout = eprload(FileName,Scaling)

if (nargout<0) || (nargout>4)
  error('Please provide 1, 2, 3 or 4 output arguments!');
end

if (nargin<1), FileName = pwd; end

if (nargin<2)
  Scaling = '';
end

LocationType = exist(FileName,'file');

if (LocationType==7), % a directory
  CurrDir = pwd;
  cd(FileName);
  [uiFile,uiPath] = uigetfile({...
    '*.DTA;*.dta;*.spc','Bruker (*.dta,*.spc)';...
    '*.d01','SpecMan (*.d01)';...
    '*.spe;*.xml','Magnettech (*.spe,*.xml)';...
    '*.esr','Active Spectrum (*.esr)';...
    '*.spk;*.ref','Varian (*.spk,*.ref)';...
    '*.eco','qese/tryscore (*.eco)';...
    '*.d00','ETH/WIS (*.d00)';...
    '*.plt','Magres (*.plt)'},...
    'Load EPR data file...');
  cd(CurrDir);
  if (uiFile==0),
    varargout = cell(1,nargout);
    return;
  end
  FileName = [uiPath uiFile];
end

% Initialize output arguments
Abscissa = [];
Data = [];  
Parameters = [];

% General remarks
%-----------------------------------------------------------
% No complete format specification for any format was available.
% Code for all formats except BES3T is a Matlab translation
% of cvt, a c program in use at ETH. Code for BES3T is
% built according to the "specification" of this format
% in the help file sharedHelp/BES3T.voc of Xepr Version 2.2b.
%-----------------------------------------------------------

% Decompose file name, supply default extension .DTA
[p,Name,FileExtension] = fileparts(FileName);
FullBaseName = fullfile(p,Name);

if isempty(FileExtension)
  if exist([FullBaseName '.dta'],'file'), FileExtension = '.dta'; end
  if exist([FullBaseName '.DTA'],'file'), FileExtension = '.DTA'; end
  if exist([FullBaseName '.spc'],'file'), FileExtension = '.spc'; end
end

FileName = [FullBaseName FileExtension];
LocationType = exist(FileName,'file');
if any(LocationType==[0 1 5 8]), % not a file/directory
  error('The file or directory %s does not exist!',FileName);
end

% Scaling works only for par/spc files (ECS106, ESP, etc)
if ~isempty(Scaling)
  S_ = Scaling;
  S_(S_=='n' | S_=='P' | S_=='G' | S_=='T' | S_=='c') = [];
  if ~isempty(S_)
    error('Scaling can only contain ''n'', ''P'', ''G'', ''T'', and ''c''.');
  end
end

% Determine file format from file extension
switch upper(FileExtension)
  case {'.DTA','.DSC'}, FileFormat = 'BrukerBES3T';
  case {'.PAR','.SPC'}, FileFormat = 'BrukerESP';
  case '.D01', FileFormat = 'SpecMan';
  case '.SPE', FileFormat = 'MagnettechBinary';
  case '.XML', FileFormat = 'MagnettechXML';
  case '.ESR', FileFormat = 'ActiveSpectrum';
  case '.DAT', FileFormat = 'Adani';
  case '.ECO', FileFormat = 'qese/tryscore';
  case '.PLT', FileFormat = 'MAGRES';
  case {'.SPK','.REF'}, FileFormat = 'VarianETH';
  case '.D00', FileFormat = 'WeizmannETH';
  otherwise
    % Test for JEOL file
    h = fopen(FileName,'r');
    if (h<0), error(['Could not open ' FileName]); end
    processType = fread(h,16,'*char');  % first 16 characters
    fclose(h);
    ok = regexp(processType.','^spin|^cAcqu|^endor|^pAcqu|^cidep|^sod|^iso|^ani','once');
    if ~isempty(ok)
      FileFormat = 'JEOL';
    else
      error('Unsupported file extension %s',FileExtension);
    end
end

switch FileFormat

case 'BrukerBES3T'
  %--------------------------------------------------------
  % BES3T file processing
  % (Bruker EPR Standard for Spectrum Storage and Transfer)
  %    .DSC: descriptor file
  %    .DTA: data file
  % used on Bruker ELEXSYS and EMX machines
  % Code based on BES3T version 1.2 (Xepr 2.1)
  %--------------------------------------------------------

  if ismember(FileExtension,{'.DSC','.DTA'})
    ParExtension = '.DSC';
    SpcExtension = '.DTA';
  else
    ParExtension = '.dsc';
    SpcExtension = '.dta';
  end
  
  % Read descriptor file (contains key-value pairs)
  [Parameters,err] = readDSCfile([FullBaseName ParExtension]);
  error(err);
  
  % IKKF: Complex-data Flag
  % CPLX indicates complex data, REAL indicates real data.
  if isfield(Parameters,'IKKF')
    parts = regexp(Parameters.IKKF,',','split');
    nDataValues = numel(parts); % number of data values per parameter point
    for k = 1:nDataValues
      switch parts{k}
        case 'CPLX', isComplex(k) = 1;
        case 'REAL', isComplex(k) = 0;
        otherwise, error('Unknown value for keyword IKKF in .DSC file!');
      end
    end
  else
    warning('Keyword IKKF not found in .DSC file! Assuming IKKF=REAL.');
    isComplex = 0;
    nDataValues = 1;
  end
  
  % XPTS: X Points   YPTS: Y Points   ZPTS: Z Points
  % XPTS, YPTS, ZPTS specify the number of data points in
  %  x, y and z dimension.
  if isfield(Parameters,'XPTS'), nx = sscanf(Parameters.XPTS,'%f'); else error('No XPTS in DSC file.'); end
  if isfield(Parameters,'YPTS'), ny = sscanf(Parameters.YPTS,'%f'); else ny = 1; end
  if isfield(Parameters,'ZPTS'), nz = sscanf(Parameters.ZPTS,'%f'); else nz = 1; end
  Dimensions = [nx,ny,nz];
  
  % BSEQ: Byte Sequence
  % BSEQ describes the byte order of the data. BIG means big-endian,
  % LIT means little-endian. Sun and Motorola-based systems are
  % big-endian (MSB first), Intel-based system little-endian (LSB first).
  if isfield(Parameters,'BSEQ')
    switch Parameters.BSEQ
    case 'BIG', ByteOrder = 'ieee-be';
    case 'LIT', ByteOrder = 'ieee-le';
    otherwise, error('Unknown value for keyword BSEQ in .DSC file!');
    end
  else
    warning('Keyword BSEQ not found in .DSC file! Assuming BSEQ=BIG.');
    ByteOrder = 'ieee-be';
  end
  
  % IRFMT: Item Real Format
  % IIFMT: Item Imaginary Format
  % Data format tag of BES3T is IRFMT for the real part and IIFMT
  % for the imaginary part.
  if isfield(Parameters,'IRFMT')
    parts = regexp(Parameters.IRFMT,',','split');
    if numel(parts)~=nDataValues
      error('Problem in BES3T DSC file: inconsistent IKKF and IRFMT fields.');
    end
    for k = 1:nDataValues
      switch upper(parts{k})
        case 'C', NumberFormat = 'int8';
        case 'S', NumberFormat = 'int16';
        case 'I', NumberFormat = 'int32';
        case 'F', NumberFormat = 'float32';
        case 'D', NumberFormat = 'float64';
        case 'A', error('Cannot read BES3T data in ASCII format!');
        case {'0','N'}, error('No BES3T data!');
        otherwise
          error('Unknown value for keyword IRFMT in .DSC file!');
      end
    end
  else
    error('Keyword IRFMT not found in .DSC file!');
  end
  
  % We enforce IRFMT and IIFMT to be identical.
  if isfield(Parameters,'IIFMT')
    if any(upper(Parameters.IIFMT)~=upper(Parameters.IRFMT))
      error('IRFMT and IIFMT in DSC file must be identical.');
    end
  end

  % Construct abscissa vectors
  AxisNames = {'X','Y','Z'};
  for a=3:-1:1
    if (Dimensions(a)<=1), continue; end
    AxisType = Parameters.([AxisNames{a} 'TYP']);
    if strcmp(AxisType,'IGD')
      % Nonlinear axis -> Try to read companion file (.XGF, .YGF, .ZGF)
      fg = fopen([FullBaseName '.' AxisNames{a} 'GF'],'r',ByteOrder);
      if fg>0
        % Here we should check for the number format in
        % XFMT/YFMT/ZFMT instead of assuming 'float64'.
        Abscissa{a} = fread(fg,Dimensions(a),'float64',ByteOrder);
        fclose(fg);
      else
        warning('Could not read companion file for nonlinear axis.');
        AxisType = 'IDX';
      end
    end
    if strcmp(AxisType,'IDX')
      Minimum(a) = sscanf(Parameters.([AxisNames{a} 'MIN']),'%f');
      Width(a) = sscanf(Parameters.([AxisNames{a} 'WID']),'%f');
      if (Width(a)==0)
        fprintf('Warning: %s range has zero width.\n',AxisNames{a});
        Minimum(a) = 1;
        Width(a) = Dimensions(a)-1;
      end
      Abscissa{a} = Minimum(a) + linspace(0,Width(a),Dimensions(a));
    end
    if strcmp(AxisType,'NTUP')
      error('Cannot read data with NTUP axes.');
    end
  end
  if (numel(Abscissa)==1)
    Abscissa = Abscissa{1}(:);
  end
    
  % Read data matrix. 
  Data = getmatrix([FullBaseName,SpcExtension],Dimensions,NumberFormat,ByteOrder,isComplex);

  % Scale spectrum/spectra
  if ~isempty(Scaling)

    % #SPL/EXPT: type of experiment
    cwExperiment = strcmp(Parameters.EXPT,'CW');

    % #DSL/signalChannel/SctNorm: indicates whether CW data are already scaled
    if ~isfield(Parameters,'SctNorm')
      %error('Missing SctNorm field in the DSC file. Cannot determine whether data is already scaled')
      DataPreScaled = 0;
    else
      DataPreScaled = strcmpi(Parameters.SctNorm,'true');
    end
    
    % Number of scans
    if any(Scaling=='n')
      % #SPL/AVGS: number of averages
      if ~isfield(Parameters,'AVGS')
        error('Missing AVGS field in the DSC file.')
      end
      nAverages = sscanf(Parameters.AVGS,'%d');
      if DataPreScaled
        error('Scaling by number of scans not possible,\nsince data in DSC/DTA are already averaged\nover %d scans.',nAverages);
      else
        Data = Data/nAverages;
      end
    end

    % Receiver gain
    if cwExperiment
      if any(Scaling=='G')
        % #SPL/RCAG: receiver gain in decibels
        if ~isfield(Parameters,'RCAG')
          error('Cannot scale by receiver gain, since RCAG in the DSC file is missing.');
        end
        ReceiverGaindB = sscanf(Parameters.RCAG,'%f');
        ReceiverGain = 10^(ReceiverGaindB/10);
        % Xenon (according to Feb 2011 manual) uses 20*10^(RCAG/20)
        % ReceiverGain = 20*10^(ReceiverGaindB/20);
        Data = Data/ReceiverGain;
      end
    end
    
    % Conversion/sampling time
    if cwExperiment && any(Scaling=='c')
      %if ~DataPreScaled
        % #SPL/SPTP: sampling time in seconds
        if ~isfield(Parameters,'SPTP')
          error('Cannot scale by sampling time, since SPTP in the DSC file is missing.');
        end
        % Xenon (according to Feb 2011 manual) already scaled data by ConvTime if
        % normalization is specified (SctNorm=True). Question: which units are used?
        % Xepr (2.6b.2) scales by conversion time even if data normalization is
        % switched off!
        ConversionTime = sscanf(Parameters.SPTP,'%f'); % in seconds
        ConversionTime = ConversionTime*1000; % s -> ms
        Data = Data/ConversionTime;
      %else
        %error('Scaling by conversion time not possible,\nsince data in DSC/DTA are already scaled.');
      %end
    end
  
    % Microwave power
    if cwExperiment
      if any(Scaling=='P')
        % #SPL/MWPW: microwave power in watt
        if ~isfield(Parameters,'MWPW')
          error('Cannot scale by power, since MWPW is absent in parameter file.');
        end
        mwPower = sscanf(Parameters.MWPW,'%f')*1000; % in milliwatt
        Data = Data/sqrt(mwPower);
      end
    else
      if any(Scaling=='P')
        error('Cannot scale by microwave power, since these are not CW-EPR data.');
      end
    end

    % Temperature
    if any(Scaling=='T')
      % #SPL/STMP: temperature in kelvin
      if ~isfield(Parameters,'STMP')
        error('Cannot scale by temperature, since STMP in the DSC file is missing.');
      end
      Temperature = sscanf(Parameters.STMP,'%f');
      Data = Data*Temperature;
    end

  end
  
  Parameters = parseparams(Parameters);

case 'BrukerESP'
  %--------------------------------------------------
  % ESP data file processing
  %   Bruker ECS machines
  %   Bruker ESP machines
  %   Bruker WinEPR, Simfonia
  %--------------------------------------------------
  
  % Read parameter file (contains key-value pairs)
  ParExtension = '.par';
  SpcExtension = '.spc';
  if ismember(FileExtension,{'.PAR','.SPC'})
    ParExtension = upper(ParExtension);
    SpcExtension = upper(SpcExtension);
  end
  [Parameters,err] = readPARfile([FullBaseName,ParExtension]);
  error(err);
  
  % FileType: flag for specific file format
  % w   Windows machines, WinEPR
  % c   ESP machines, cw EPR data
  % p   ESP machines, pulse EPR data
  FileType = 'c';
  
  TwoD = 0; % Flag for two-dimensional data
  isComplex = 0; % Flag for complex data
  nx = 1024;
  ny = 1;
  
  % For DOS ByteOrder is ieee-le, in all other cases ieee-be
  if isfield(Parameters,'DOS')
    Endian = 'ieee-le';
    FileType = 'w';
  else
    Endian = 'ieee-be';
  end
  
  % Analyse data type flags stored in JSS.
  if isfield(Parameters,'JSS')
    Flags = sscanf(Parameters.JSS,'%f');
    isComplex = bitget(Flags,5);
    TwoD = bitget(Flags,13);
  end
  
  % If present, SSX contains the number of x points.
  if isfield(Parameters,'SSX')
    if TwoD,
      if FileType=='c', FileType='p'; end
      nx = sscanf(Parameters.SSX,'%f');
      if isComplex, nx = nx/2; end
    end
  end
  
  % If present, SSY contains the number of y points.
  if isfield(Parameters,'SSY')
    if TwoD,
      if FileType=='c', FileType='p'; end
      ny = sscanf(Parameters.SSY,'%f');
    end
  end
  
  % If present, ANZ contains the total number of points.
  if isfield(Parameters,'ANZ')
    nAnz = sscanf(Parameters.ANZ,'%f');
    if ~TwoD,
      if FileType=='c', FileType='p'; end
      nx = nAnz;
      if isComplex, nx = nx/2; end
    else
      if (nx*ny~=nAnz)
        error('Two-dimensional data: SSX, SSY and ANZ in .par file are inconsistent.');
      end
    end
  end
  
  % If present, RES contains the number of x points.
  if isfield(Parameters,'RES')
    nx = sscanf(Parameters.RES,'%f');
  end
  % If present, REY contains the number of y points.
  if isfield(Parameters,'REY')
    ny = sscanf(Parameters.REY,'%f');
  end

  % If present, XPLS contains the number of x points.
  if isfield(Parameters,'XPLS')
    nx = sscanf(Parameters.XPLS,'%f');
  end
  
  % Set number format
  switch FileType
  case 'c', NumberFormat = 'int32';
  case 'w', NumberFormat = 'float'; % WinEPR/Simfonia: single float
  case 'p', NumberFormat = 'int32'; % old: 'float'
  end
  
  % Construct abscissa vector
  if (nx>1)

    % Get experiment type
    if ~isfield(Parameters,'JEX'), Parameters.JEX = 'field-sweep'; end
    if ~isfield(Parameters,'JEY'), Parameters.JEY = ''; end
    JEX_Endor = strcmp(Parameters.JEX,'ENDOR');
    JEX_TimeSweep = strcmp(Parameters.JEX,'Time-Sweep');
    JEY_PowerSweep = strcmp(Parameters.JEY,'mw-power-sweep');

    % Convert values of all possible range keywords
    %-------------------------------------------------------
    GST = []; GSI = []; HCF = []; HSW = []; 
    XXLB = []; XXWI = []; XYLB = []; XYWI = [];
    if isfield(Parameters,'HCF')
      HCF = sscanf(Parameters.HCF,'%f');
    end
    if isfield(Parameters,'HSW')
      HSW = sscanf(Parameters.HSW,'%f');
    end
    if isfield(Parameters,'GST')
      GST = sscanf(Parameters.GST,'%f');
    end
    if isfield(Parameters,'GSI')
      GSI = sscanf(Parameters.GSI,'%f');
    end
    
    % XXLB, XXWI, XYLB, XYWI
    % In files from the pulse S-band spectrometer at ETH,
    % both HSW/HCF and GST/GSI are absent.
    if isfield(Parameters,'XXLB')
      XXLB = sscanf(Parameters.XXLB,'%f');
    end
    if isfield(Parameters,'XXWI')
      XXWI = sscanf(Parameters.XXWI,'%f');
    end
    if isfield(Parameters,'XYLB')
      XYLB = sscanf(Parameters.XYLB,'%f');
    end
    if isfield(Parameters,'XYWI')
      XYWI = sscanf(Parameters.XYWI,'%f');
    end

    % Determine which abscissa range parameters to take
    %-----------------------------------------------------------
    TakeGH = 0; % 1: take GST/GSI,  2: take HCF/HSW, 3: try XXLB
    if JEX_Endor
      % Endor experiment: take GST/GSI
      TakeGH = 1;
    elseif ~isempty(XXLB) && ~isempty(XXWI) && ~isempty(XYLB) && ~isempty(XYWI)
      % EMX 2D data -> use XXLB/XXWI/XYLB/XYWI
      TakeGH = 3;
    elseif ~isempty(HCF) && ~isempty(HSW) && ~isempty(GST) && ~isempty(GSI)
      % All fields present: take GST/GSI (even if inconsistent
      % with HCF/HSW) (not sure this is correct in all cases)
      TakeGH = 1;
    elseif ~isempty(HCF) && ~isempty(HSW)
      % Only HCF and HSW given: take them
      TakeGH = 2;
    elseif ~isempty(GST) && ~isempty(GSI)
      TakeGH = 1;
    elseif isempty(GSI) && isempty(HSW)
      HSW = 50;
      TakeGH = 2;
    elseif isempty(HCF)
      TakeGH = 3;
    end
    
    % Construct abscissa vector
    %----------------------------------------------------
    if JEX_TimeSweep
      if isfield(Parameters,'RCT')
        ConversionTime = sscanf(Parameters.RCT,'%f');
      else
        ConversionTime = 1;
      end
      Abscissa = (0:nx-1)*ConversionTime/1e3;
    else
      Abscissa = [];
      if (TakeGH==1)
        Abscissa = GST + GSI*linspace(0,1,nx);
      elseif (TakeGH==2)
        Abscissa = HCF + HSW/2*linspace(-1,1,nx);
      elseif (TakeGH==3)
        if ~isempty(XXLB) && ~isempty(XXWI)
          if ~isempty(XYLB) && ~isempty(XYWI)
            Abscissa{1} = XXLB + linspace(0,XXWI,nx);
            Abscissa{2} = XYLB + linspace(0,XYWI,ny);
          else
            Abscissa = XXLB + linspace(0,XXWI,nx);
          end
        end
      else
        error('Could not determine abscissa range from parameter file!');
      end
    end

    
  end
  
  % Slice of 2D data, as saved by WinEPR: RES/REY refer to
  % original 2D size, but JSS 2D flag is not set -> 1D data
  if ~TwoD && (ny>1), ny = 1; end
  
  % Read data file.
  nz = 1;
  Dimensions = [nx ny nz];
  Data = getmatrix([FullBaseName,SpcExtension],Dimensions,NumberFormat,Endian,isComplex);

  % Scale spectrum/spectra
  if ~isempty(Scaling)

    % Number of scans
    if any(Scaling=='n')
      if ~isfield(Parameters,'JSD')
        error('Cannot scale by number of scans, since JSD is absent in parameter file.');
      end
      nScansDone = sscanf(Parameters.JSD,'%f');
      Data = Data/nScansDone;
    end

    % Receiver gain
    if any(Scaling=='G')
      if ~isfield(Parameters,'RRG')
        %Parameters.RRG = '2e4'; % default value on UC Davis ECS106
        error('Cannot scale by gain, since RRG is absent in parameter file.');
      end
      ReceiverGain = sscanf(Parameters.RRG,'%f');
      Data = Data/ReceiverGain;
    end

    % Microwave power
    if any(Scaling=='P')
      if ~isfield(Parameters,'MP')
        error('Cannot scale by power, since MP is absent in parameter file.');
      end
      if ~JEY_PowerSweep
        mwPower = sscanf(Parameters.MP,'%f'); % in milliwatt
        Data = Data/sqrt(mwPower);
      else
        % 2D power sweep, power along second dimension
        nPowers = size(Data,2);
        dB = XYLB+linspace(0,XYWI,nPowers);
        mwPower = sscanf(Parameters.MP,'%f'); % in milliwatt
        mwPower = mwPower.*10.^(-dB/10);
        for iPower = 1:nPowers
          Data(:,iPower) = Data(:,iPower)/sqrt(mwPower(iPower));
        end
      end
    end

    % Temperature
    if any(Scaling=='T')
      if ~isfield(Parameters,'TE')
        error('Cannot scale by temperature, since TE is absent in parameter file.');
      end
      Temperature = sscanf(Parameters.TE,'%f'); % in kelvin
      if (Temperature==0)
        error('Cannot scale by temperature, since TE is zero in parameter file.');
      end
      Data = Data*Temperature;
    end

    % Conversion/sampling time
    if any(Scaling=='c')
      if ~isfield(Parameters,'RCT')
        error('Cannot scale by sampling time, since RCT in the .par file is missing.');
      end
      ConversionTime = sscanf(Parameters.RCT,'%f'); % in milliseconds
      Data = Data/ConversionTime;
    end

  end
  
  Parameters = parseparams(Parameters);

case 'SpecMan'
  %----------------------------------------------
  % d01 file processing
  %   SpecMan
  %----------------------------------------------  
  
  % Read parameter file
  % -> not implemented
  
  % Open the .d01 file and error if unsuccessful
  [h,ignore] = fopen(FileName,'r','ieee-le');
  if (h<0), error(['Could not open ' FileName]); end
  
  nDataSets = fread(h,1,'uint32');  % number of headers, re/im etc.
  ndim = 1;
  
  % Number format: 0-double(64bit),1-float(32bit)
  FormatID = fread(h,1,'uint32'); 
  switch FormatID
    case 1, DataFormat = 'float32';
    case 0, DataFormat = 'double';
    otherwise, error('Could not determine format in %s',FileName);
  end
 
  for iDataSet = 1:nDataSets
    ndim2(iDataSet) = fread(h,1,'int32');  % re/im ?
    dims(:,iDataSet) = fread(h,4,'int32');
    nTotal(iDataSet) = fread(h,1,'int32' );
  end
  dims(dims==0) = 1;

  Data = fread(h,sum(nTotal),DataFormat);

  %try
  switch (nDataSets)
  case 2,
    Data = complex(Data(1:nTotal),Data(nTotal+1:end));
    Data = reshape(Data,dims(:,1).');
  case 1,
    Data = reshape(Data,dims(:).');
  end
  %end
  
  % Close data file
  St = fclose(h);
  if (St<0), error(['Unable to close ' FileName]); end

  if ~isempty(Scaling)
    error('Scaling does not work for this file type.');
  end
  
  Parameters = [];

case 'MagnettechBinary'
  %--------------------------------------------------------------------------
  %   Binary file format of older Magnettech spectrometers (MS400 and prior)
  %--------------------------------------------------------------------------
  
  hMagnettechFile = fopen(FileName,'r','ieee-le');
  if (hMagnettechFile<0)
    error('Could not open Magnettech spectrometer file %s.',FileName);
  end
  
  nPoints = 4096; % all files have the same number of points
  [Data,count] = fread(hMagnettechFile,nPoints,'int16');
  if (count<nPoints)
    error('Could not read %d of 4096 data points from %s.',count,FileName);
  end
  [paramdata,count] = fread(hMagnettechFile,16*2,'int16');
  if (count<16*2)
    error('Could not read %d of 16 parameters from %s.',count/2,FileName);
  end
  fclose(hMagnettechFile);

  paramdata = reshape(paramdata,[2 16]).';
  paramdata = paramdata(:,1) + paramdata(:,2)/100;
  
  Parameters.B0_Field = paramdata(1)/10;
  Parameters.B0_Scan = paramdata(2)/10;
  Parameters.Modulation = paramdata(3)/10000;
  Parameters.MW_Attenuation = paramdata(4);
  Parameters.ScanTime = paramdata(5);
  Parameters.GainMantissa = paramdata(6);
  Parameters.GainExponent = paramdata(7);
  Parameters.Gain = Parameters.GainMantissa*10^Parameters.GainExponent;
  Parameters.Number = paramdata(8);
  Parameters.Time_const = paramdata(10);
  Parameters.Samples = paramdata(13);
  
  Abscissa = Parameters.B0_Field + linspace(-1/2,1/2,numel(Data))*Parameters.B0_Scan;
  Abscissa = Abscissa(:);
  
  if ~isempty(Scaling)
    error('Scaling does not work for Magnettech files.');
  end
  
case 'MagnettechXML'
  %------------------------------------------------------------------
  %   XML file format of newer Magnettech spectrometers (MS5000)
  %------------------------------------------------------------------
  Document = xmlread(FileName);
  MainNode = Document.getFirstChild;
  if isempty(MainNode)
    str = '';
  else
    str = MainNode.getNodeName;
  end
  if ~strcmpi(str,'ESRXmlFile')
    error('File %s is not a Magnettech xml file.',FileName);
  end
  
  % Read in all the data
  curveList = MainNode.getElementsByTagName('Curve');
  nCurves = curveList.getLength;
  base64 = org.apache.commons.codec.binary.Base64; % use java method for base64 decoding
  for iCurve = 0:nCurves-1
    curve_ = curveList.item(iCurve);
    Mode = char(curve_.getAttribute('Mode'));
    if ~strcmp(Mode,'Pre'), continue; end
    Name = char(curve_.getAttribute('YType'));
    XOffset = char(curve_.getAttribute('XOffset'));
    XOffset = sscanf(XOffset,'%f');
    XSlope = char(curve_.getAttribute('XSlope'));
    XSlope = sscanf(XSlope,'%f');
    x = char(curve_.getTextContent);
    if isempty(x)
      data = [];
    else
      x = typecast(int8(x),'uint8'); % typecast without changing the underlying data
      bytestream_ = base64.decode(x); % decode
      bytestream_(9:9:end) = []; % remove termination zeros
      data = typecast(bytestream_,'double'); % typecast without changing the underlying data
    end
    Curves.(Name).data = data;
    Curves.(Name).t = XOffset + (0:numel(data)-1)*XSlope;
  end
  
  % Add attributes from Measurement node to Paramater structure
  MeasurementNode = MainNode.getElementsByTagName('Measurement');
  AttribList = MeasurementNode.item(0).getAttributes;
  for k=0:AttribList.getLength-1
    PName = AttribList.item(k).getName;
    PVal = AttribList.item(k).getTextContent;
    PName = ['Measurement_' char(PName)];
    Parameters.(char(PName)) = char(PVal);
  end
  
  % Add all children Param nodes from Parameters node to Parameter structure
  ParameterList = MainNode.getElementsByTagName('Param');
  for k=0:ParameterList.getLength-1
    PName = ParameterList.item(k).getAttribute('Name');
    P_ = ParameterList.item(k).getTextContent;
    Parameters.(char(PName)) = char(P_);
  end
  
  Abscissa = interp1(Curves.BField.t,Curves.BField.data,Curves.MW_Absorption.t);
  Abscissa = Abscissa(:);
  Data = Curves.MW_Absorption.data(:);
  Parameters = parseparams(Parameters);
  
case 'ActiveSpectrum'
  %------------------------------------------------------------------
  %   ESR file format of Active Spectrum spectrometers
  %------------------------------------------------------------------
  allLines = textread(FileName,'%s','whitespace','','delimiter','\n');
  nLines = numel(allLines);
  
  % Find start of data
  for idx = 1:nLines
    found = strncmp(allLines{idx},'FIELD (G)',9);
    if found; break; end
  end
  if (~found)
    error('Could not find start of data in file %s',FileName);
  end
  
  dataLines = allLines(idx+1:end);
  nPoints = numel(dataLines);
  
  for idx = 1:nPoints
    data(idx,:) = sscanf(dataLines{idx},'%f',2);
  end
  Abscissa = data(:,1);
  Data = data(:,2);
  Parameters = [];
  
case 'Adani'
  %------------------------------------------------------------------
  %   Text-based file format of Adani spectrometers
  %------------------------------------------------------------------
  allLines = textread(FileName,'%s','whitespace','','delimiter','\n');
  nLines = numel(allLines);

  Line1 = '======================== Parameters: ========================';
  if ~strncmp(allLines{1},Line1,length(Line1))
    error('The file %s is not an Adani spectrometer file',FileName);
  end
  Line2 = '=============================================================';
  for idx = 1:nLines
    found = strncmp(allLines{idx},Line2,length(Line2));
    if found; break; end
  end
  if (~found)
    error('Could not find start of data in file %s',FileName);
  end
  nPoints = nLines - idx;
  data = zeros(nPoints,3);
  for p=1:nPoints
    L_ = allLines{idx+p};
    L_(L_==',') = '.';
    data(p,:) = sscanf(L_,'%f',3);
  end
  Abscissa = data(:,2);
  Data = data(:,3);

  
case 'JEOL'
  %--------------------------------------------------
  % JEOL file format for JES-FA and JES-X3
  % (based on official documentation)
  %--------------------------------------------------
  [Abscissa,Data,Parameters] = eprload_jeol(FileName);
  
case 'qese/tryscore'
  %--------------------------------------------------
  % ECO file processing
  %   qese     old ETH acquisition software
  %   tryscore Weizmann HYSCORE simulation program
  %--------------------------------------------------

  % open file
  fid = fopen(FileName,'r');
  if fid<0, error(['Could not open ' FileName]); end
  
  % read first line: nx ny Complex
  Data = sscanf(fgetl(fid),'%i%i%i',3)';
  
  % set dimensions and complex flag
  switch length(Data)
  case 3, Dims = Data([1 2]); isComplex = Data(3);
  case 2, Dims = Data; isComplex = 0;
  case 1, Dims = [Data 1]; isComplex = 0;
  end
  
  % read data
  Data = fscanf(fid,'%f',prod(Dims)*(isComplex+1));
  
  % combine to complex and reshape
  if isComplex
    Data = complex(Data(1:2:end),Data(2:2:end));
  end
  Data = reshape(Data,Dims);
  
  % close file
  St = fclose(fid);
  if St<0, error('Unable to close ECO file.'); end
  
  if ~isempty(Scaling)
    error('Scaling does not work for this file type.');
  end
  
  Parameters = [];

case 'MAGRES'
  %--------------------------------------------------
  % PLT file processing
  %   MAGRES  Nijmegen EPR/ENDOR simulation program
  %--------------------------------------------------
  
  [Line,found] = findtagsMAGRES(FileName,{'DATA'});
  if found(1), nx = str2double(Line{1}); else nx=0; end
  if ~nx,
    error('Unable to determine number of x points in PLT file.');
  end
  
  fid = fopen(FileName,'r');
  if (fid<0), error(['Could not open ' FileName]); end
  
  for k=1:3, fgetl(fid); end
  
  % read data
  ny = 1;
  [Data,N] = fscanf(fid,'%f',[nx,ny]);
  if (N<nx*ny),
    warning('Could not read entire data set from PLT file.');
  end
  
  % close file
  St = fclose(fid);
  if St<0, error('Unable to close PLT file.'); end
  
  if ~isempty(Scaling)
    error('Scaling does not work for this file type.');
  end
  
  Parameters = [];

case 'VarianETH'
  %--------------------------------------------------
  % SPK, REF file processing
  %   Varian E9 file format (ETH specific, home-built
  %   computer acquisition system written in 1991)
  %--------------------------------------------------
  fid = fopen(FileName,'r','ieee-le');
  if fid<0, error('Could not open %s.',FileName); end
  [RawData,N] = fread(fid,inf,'float32');
  if fclose(fid)<0, error('Unable to close %s.',FileName); end
  
  K = [500 1e3 2e3 5e3 1e4];
  idx = find(N>K);
  if isempty(idx), error('File too small.'); end
  
  Data = RawData(N-K(idx(end))+1:end).';
  % No idea what the first part of such a file contains...
  % There is no documentation available...
  
  if ~isempty(Scaling)
    error('Scaling does not work for this file type.');
  end
  
  Parameters = [];
  
case 'WeizmannETH'
  %----------------------------------------------
  % d00 file processing
  %   ESE  Weizmann and ETH acquisition software
  %----------------------------------------------
  
  % Read parameter file
  % -> not implemented
  
  % open the .d00 file and error if unsuccessful
  h = fopen(FileName);
  if h<0, error(['Could not open ' FileName]); end
  
  % read in first three 16bit integers
  Dims = fread(h,3,'int16').';
  %nDims = sum(Dims>1);
  
  % read in data, complex
  Data = fread(h,[2,inf],'double');
  Data = complex(Data(1,:) ,Data(2,:));
  
  % and shape into correct array size
  Data = reshape(Data,Dims);
  
  % close data file
  St = fclose(h);
  if St<0, error('Unable to close D00 file.'); end
  %----------------------------------------------

  if ~isempty(Scaling)
    error('Scaling does not work for this file type.');
  end
  
  Parameters = [];
  
otherwise
  
  error('File format ''%s'' not implemented.',FileFormat);
  
end


switch (nargout)
  case 1
    varargout = {Data};
  case 2
    varargout = {Abscissa, Data};
  case 3
    varargout = {Abscissa, Data, Parameters};
  case 4
    varargout = {Abscissa, Data, Parameters, FileName};
  case 0
    if isempty(Data), return; end
    if ~iscell(Data), Data = {Data}; end
    nDataSets = numel(Data);
    for k = 1:nDataSets
      subplot(nDataSets,1,k);
      if min(size(Data{k}))==1
        if isreal(Data{k})
          plot(Abscissa,Data{k});
        else
          plot(Abscissa,real(Data{k}),'b',Abscissa,imag(Data{k}),'r');
        end
        if (nDataSets>1)
          title([FileName sprintf(', dataset %d',k)],'Interpreter','none');
        else
          title(FileName,'Interpreter','none');
        end
        axis tight
        if ~isreal(Data{k})
          legend('real','imag');
          legend boxoff
        end
      else
        pcolor(real(Data{k})); shading flat;
      end
    end
end

return

%--------------------------------------------------
function out = getmatrix(FileName,Dims,NumberFormat,ByteOrder,isComplex)

% Open data file, error if fail.
FileID = fopen(FileName,'r',ByteOrder);
if (FileID<1), error('Unable to open data file %s',FileName); end

% Calculate expected number of elements and read in.
% Real and imaginary data are interspersed.
nDataValuesPerPoint = numel(isComplex);
nRealsPerPoint = sum(isComplex+1);
N = nRealsPerPoint*prod(Dims);

[x,effN] = fread(FileID,N,NumberFormat);
if (effN~=N)
  error('Unable to read all expected data.');
end

% Close data file
CloseStatus = fclose(FileID);
if (CloseStatus<0), error('Unable to close data file %s',FileName); end

% Reshape data and combine real and imaginary data to complex.
x = reshape(x,nRealsPerPoint,[]);
for k = 1:nDataValuesPerPoint
  if isComplex(k)
    data{k} = complex(x(k,:),x(k+1,:)).';
    x(k+1,:) = [];
  else
    data{k} = x(k,:);
  end
end

% Reshape to matrix and permute dimensions if wanted.
DimOrder = 1:3;
for k = 1:nDataValuesPerPoint
  out{k} = reshape(data{k},Dims);
end

if numel(out)==1, out = out{1}; end

return
%--------------------------------------------------

%--------------------------------------------------
function [out,found] = findtagsMAGRES(FileName,TagList)

% open file
fid = fopen(FileName,'r');
if fid<0, error(['Could not open ' FileName]); end

found = zeros(1,length(TagList));
out = cell(1,length(TagList));
while ~feof(fid)
  Line = fgetl(fid);
  whitespace = find(isspace(Line)); % space or tab
  if ~isempty(whitespace),
    endTag = whitespace(1)-1;
    if endTag>0
      I = strcmp(Line(1:endTag),TagList);
      if ~isempty(I),
        out{I} = fliplr(deblank(Line(end:-1:endTag+1)));
        found(I) = 1;
      end
    end
  end
end

% close file
St = fclose(fid);
if St<0, error('Unable to close data file.'); end

return
%--------------------------------------------------


function [Parameters,err] = readPARfile(PARFileName)

Parameters = [];
err = [];

if exist(PARFileName,'file')
  allLines = textread(PARFileName,'%s','whitespace','','delimiter','\n');
else
  err = sprintf('Cannot find the file %s.',PARFileName);
  return
end

for k = 1:numel(allLines)

  line = allLines{k};
  if isempty(line), continue; end
  
  [Key,n,err_,idx] = sscanf(line,'%s',1);
  if isempty(Key); continue; end
  
  if ~isletter(Key(1)), continue; end
  
  Value = deblank(line(end:-1:idx));
  Value = deblank(Value(end:-1:1));
  if ~isempty(Value)
    if Value([1 end])=='''', % remove leading and trailing quotes
      Value([1 end]) = [];
    end
  end
  
  % set field in output structure
  Parameters.(Key) = Value;
  
end

return

%---------------------------------------------------------------
function [Parameters,err] = readDSCfile(DSCFileName)

Parameters = [];
err = [];

if exist(DSCFileName,'file')
  bufferSize = 200000; % needs to be large because of AWGPrg line
  allLines = textread(DSCFileName,'%s','whitespace','','delimiter','\n','bufsize',bufferSize);
else
  err = sprintf('Cannot find the file %s.',DSCFileName);
  return
end

for k=1:numel(allLines)

  line = allLines{k};

  % Go to next if line is empty
  if isempty(line); continue; end
  
  % If line is terminated by \, append next line
  if (line(end)=='\')
    k2 = k+1;
    while (allLines{k2}(end)=='\')
      line = [line(1:end-1) allLines{k2}];
      allLines{k2} = '';
      k2 = k2 + 1;
    end
    line(end) = '';
    % Replace all \n with newline character
    line = sprintf(line);
  end
  
  [Key,Value] = strtok(line);
  if isempty(Key); continue; end
  
  % If key is not valid, go to next line.
  if ~isletter(Key(1)),
    % Stop reading when Manipulation History Layer is reached.
    if strcmpi(Key,'#MHL'); break; end
    continue;
  end
  
  Value = deblank(Value(end:-1:1)); Value = deblank(Value(end:-1:1));
  
  if ~isempty(Value)
    if Value([1 end])=='''',
       Value([1 end]) = [];
    end
  end
  
  % Set field in output structure.
  Parameters.(Key) = Value;
  
end

return

%-----------------------------------------------------------------
function Pout = parseparams(ParamsIn)

Pout = ParamsIn;

Fields = fieldnames(Pout);
for iField = 1:numel(Fields)
  v = Pout.(Fields{iField});
  if isempty(v), continue; end
  if strcmpi(v,'true')
    v_num = true;
  elseif strcmpi(v,'false')
    v_num = false;
  elseif isletter(v(1))
    v_num = '';
    continue
  else
    [v_num,cnt,errormsg,nxt] = sscanf(v,'%e');
    % Converts '3345 G' to [3345] plus an error message...
    % Unclear whether conversion makes sense for the user. If not,
    % exclude such cases with
    if ~isempty(errormsg)
      v_num = '';
    end
  end
  if ~isempty(v_num)
    Pout.(Fields{iField}) = v_num(:)'; % don't use .' due to bug up to R2014a
  end
end

return
