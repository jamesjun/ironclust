function irc2klusters_v2(vcFile_prm, vcDir_out)
% J. James Jun 2019 Aug 16
% Code cited from
%   https://github.com/brendonw1/KilosortWrapper/blob/master/Kilosort2Neurosuite.m
% klusters file format:
%   http://klusters.sourceforge.net/UserManual/data-files.html#cluster-file

% Input
% ----
% EXPORT_MODE: 1 for loading all recordings to memory, 2 for paged read


[fOverwrite, fZeroBase, NUM_PC] = deal(1, 1, 3);

t1 = tic;
if nargin<2, vcDir_out=''; end
if isempty(vcDir_out)
    vcDir_out = fullfile(fileparts(vcFile_prm), 'klusters'); 
end
mkdir_(vcDir_out);

[S0, S_auto, trPc_spk, trPc2_spk, P] = load_irc2_(vcFile_prm);
nPc = min(size(trPc_spk,1), NUM_PC);
nClu = S_auto.nClu;

viTime_spk = uint64(S0.viTime_spk(:));
viClu_spk = uint32(S_auto.viClu(:));
viShank_site = get_set_(P, 'viShank_site', ones(size(P.viSite2Chan)));
[~, vcFile_base] = fileparts(vcFile_prm);
single2int16_ = @(x)int16(x/P.uV_per_bit);
single2int64_ = @(x)int64(x/P.uV_per_bit);

% Shank loop
fprintf('Exporting shanks\n'); t_shank = tic;
viSite_clu = S_auto.viSite_clu;
viShank_clu = viShank_site(viSite_clu);
viShank_unique = unique(viShank_clu);
cviSite_shank = cell(size(viShank_unique));

for iiShank = 1:numel(viShank_unique)    
    iShank1 = viShank_unique(iiShank);
    fprintf('Loading data for shank %d:\n', iShank1);
    viClu_shank1 = find(viShank_clu == iShank1);
    viSpk_shank1 = find(ismember(viClu_spk, viClu_shank1)); 
    viSite_shank1 = find(viShank_site==iShank1);
    cviSite_shank{iiShank} = viSite_shank1;
    
    % write .clu file (unit #)
    vcFile_clu1 = fullfile(vcDir_out, sprintf('%s.clu.%d', vcFile_base, iShank1));
    viClu_spk1 = viClu_spk(viSpk_shank1);    
    nClu1 = numel(viClu_shank1);
    write_file_(vcFile_clu1, [nClu1; viClu_spk1-fZeroBase], '%.0f\n'); % zero-base

    % write .res file (timing)
    vcFile_res1 = fullfile(vcDir_out, sprintf('%s.res.%d', vcFile_base, iShank1));
    viTime_spk1 = viTime_spk(viSpk_shank1);
    write_file_(vcFile_res1, viTime_spk1-fZeroBase, '%.0f\n'); % zero-base
    
    % write waveform file: [nSites1, nSamples_spk, nSpk1]
    vcFile_spk1 = fullfile(vcDir_out, sprintf('%s.spk.%d', vcFile_base, iShank1));
    trPc_spk1 = expand_pc_(trPc_spk, trPc2_spk, viSpk_shank1, S0, P);
    trPc_spk1 = trPc_spk1(:,viSite_shank1,:); % take sites for chosen shank
    trWav_spk1 = pc2wav_(trPc_spk1, S0.mrPv_global);
    write_file_(vcFile_spk1, single2int16_(permute(trWav_spk1, [2,1,3]))); 
    trWav_spk1 = [];
    
    % write feature file
    vcFile_fet1 = fullfile(vcDir_out, sprintf('%s.fet.%d', vcFile_base, iShank1));
    write_fet_(vcFile_fet1, trPc_spk1(1:nPc,:,:), viTime_spk1);
    trPc_spk1 = [];

    fprintf('.');
end %for

% write parameter files
vcFile_par = fullfile(vcDir_out, sprintf('%s.par', vcFile_base));
write_par_(vcFile_par, cviSite_shank, P);
end %func


%--------------------------------------------------------------------------
function write_fet_(vcFile_fet1, trPc_spk1, viTime_spk1)
% trPc_spk1: [nSpk1, nPc, nSites1], 'int64';

% constantsmnFet_spk1
fZeroBase = 1;
tr2mr_ = @(x)reshape(x, [], size(x,3));
mrFet_spk1 = tr2mr_(trPc_spk1);
wranges = int64(range(mrFet_spk1,1));
wpowers = int64(sum(mrFet_spk1.^2,1)/size(mrFet_spk1,1)/100);

Fet = [int64(mrFet_spk1); wranges; wpowers; int64(viTime_spk1(:)'-fZeroBase)];
nFeatures = size(Fet, 1); 
vcFormat = ['%d', repmat('\t%d', 1, nFeatures-1), '\n'];

% write to file
t_write = tic;
fid = fopen(vcFile_fet1, 'w');
fprintf(fid, '%d\n', nFeatures);
fprintf(fid, vcFormat, Fet);
fclose(fid);
fprintf('Wrote to %s (took %0.1fs)\n', vcFile_fet1, toc(t_write));
end %func


%--------------------------------------------------------------------------
function trPc_spk1 = expand_pc_(trPc1_spk, trPc2_spk, viSpk_shank1, S0, P)

miSites = P.miSites;
[nPc, nSites_spk, nSpk] = size(trPc1_spk);
nSites = numel(P.viSite2Chan);
trPc_spk1 = zeros([nPc, nSites, nSpk], 'single');
if isempty(trPc2_spk)
    cviSite_spk = {S0.viSite_spk};
    ctrPc_spk = {trPc1_spk(:,:,viSpk_shank1)};
else
    cviSite_spk = {S0.viSite_spk, S0.viSite2_spk};
    ctrPc_spk = {trPc1_spk(:,:,viSpk_shank1), trPc2_spk(:,:,viSpk_shank1)};    
end
for iFet = 1:numel(cviSite_spk)
    cviSpk_site = vi2cell_(cviSite_spk{iFet}, nSites);
    trPc_ = ctrPc_spk{iFet};
    for iSite = 1:nSites
       viSpk1 = cviSpk_site{iSite};
       if isempty(viSpk1), continue; end
       viSite1 = miSites(:,iSite);       
       trPc_spk1(:,viSite1,viSpk1) = trPc_(:,:,viSpk1);
    end
end
end %func


%--------------------------------------------------------------------------
function [S0, S_auto, trPc_spk, trPc2_spk, P] = load_irc2_(vcFile_prm)

S0 = irc2('call', 'load0_', {vcFile_prm});
if isempty(S0), error('%s: output is not found', vcFile_prm); end
P = S0.P;
S_auto = get_(S0, 'S_auto');
assert(~isempty(S_auto), 'S_auto does not exist');

% export valid clusters only
vlKeep = S_auto.viClu>0;
[S0.vrAmp_spk, S0.viTime_spk, S0.viSite_spk, S_auto.viClu] = ...
    deal(S0.vrAmp_spk(vlKeep), S0.viTime_spk(vlKeep), S0.viSite_spk(vlKeep), S_auto.viClu(vlKeep));
if ~isempty(get_(S0, 'viSite2_spk')), S0.viSite2_spk = S0.viSite2_spk(vlKeep); end

trPc_spk = load_fet_(S0, P, 1); trPc_spk = trPc_spk(:,:,vlKeep);
trPc2_spk = load_fet_(S0, P, 2); trPc2_spk = trPc2_spk(:,:,vlKeep);
end %fnc


%--------------------------------------------------------------------------
function trWav_spk = pc2wav_(trPc_spk, mrPv)
dimm_pc = size(trPc_spk);
dimm_wav = [size(mrPv,1), dimm_pc(2), dimm_pc(3)];
trWav_spk = reshape(mrPv * reshape(trPc_spk, dimm_pc(1), []), dimm_wav);
end %func


%--------------------------------------------------------------------------
function S = makeStruct_(varargin)
%MAKESTRUCT all the inputs must be a variable. 
%don't pass function of variables. ie: abs(X)
%instead create a var AbsX an dpass that name
S = struct();
for i=1:nargin, S.(inputname(i)) =  varargin{i}; end
end %func


%--------------------------------------------------------------------------
function write_file_(vcFile, vnData, vcFormat)
% mode 1: write formatted numbers
%  write_file_(vcFile, vnData, vcFormat)
% mode 2: write binary
%  write_file_(vcFile, vnData)
% mode 3: write text (separated by new lines)
%  write_file_(vcFile, csData)

if nargin<3, vcFormat = []; end

t_write = tic;
fid=fopen(vcFile, 'w');
if ~isempty(vcFormat)
    fprintf(fid, vcFormat, vnData);
else
    if iscell(vnData)
        csLines = vnData;
        for iLine = 1:numel(csLines)
            fprintf(fid, '%s\n', csLines{iLine});
        end %for
    else
        fwrite(fid, vnData, class(vnData));
    end
end
fclose(fid);
fprintf('\tWrote to %s (took %0.1fs)\n', vcFile, toc(t_write));
end %func


%--------------------------------------------------------------------------
% write par files for each shanks (easier than writing an xml file)
function write_par_(vcFile_par, cviSite_shank, P)

[nBitsPerSample, fZeroBase, nPc] = deal(16, 1, 3);
highPass = round(P.freqLim(1));
sample_interval_us = round(1e6/P.sRateHz);
nShanks = numel(cviSite_shank);
nSites = sum(cellfun(@sum, cviSite_shank));

csLines_ = {};
csLines_{end+1} = sprintf('%d %d', nSites, nBitsPerSample);
csLines_{end+1} = sprintf('%d %d', sample_interval_us, highPass);
csLines_{end+1} = sprintf('%d', nShanks);
for iiShank = 1:nShanks
    viSites1 = cviSite_shank{iiShank} - fZeroBase;
    csLines_{end+1} = sprintf('%d, %s', numel(viSites1), sprintf('%d ', viSites1));
end
write_file_(vcFile_par, csLines_);


for iiShank = 1:nShanks
    viSite_shank1 = cviSite_shank{iiShank} - fZeroBase;
    nSites1 = numel(viSite_shank1);
    nSamples_spk = diff(P.spkLim)+1;
    
    csLines_ = {};
    csLines_{end+1} = sprintf('%d %d %d', nSites1, nSites1, sample_interval_us);
    csLines_{end+1} = sprintf('%d ', viSite_shank1);
    csLines_{end+1} = '10 2'; %  # refractory sample index after detection, RMS integration window length
    csLines_{end+1} = '90'; %  # approximate firing frequency in Hz
    csLines_{end+1} = sprintf('%d %d', nSamples_spk, 1-P.spkLim(1)); % # number of samples in each waveform, sample index of the peak
    csLines_{end+1} = '12 6'; % # window length to realign the spikes, sample index of the peak (detection program)
    csLines_{end+1} = '4 4'; % # number of samples (before and after the peak) to use for reconstruction and features
    csLines_{end+1} = sprintf('%d %d', nPc, nSamples_spk); % # number of principal components (features) per electrode, number of samples used for the PCA
    csLines_{end+1} = sprintf('%d', highPass);
    
    vcFile_par1 = strrep(vcFile_par, '.par', sprintf('.par.%d', iiShank));
    write_file_(vcFile_par1, csLines_);
end % for
end %func


%--------------------------------------------------------------------------
% save filtered waveform in a transposed format (_wav.jrc)
% supports single file only and non-transposed
function save_spk_klusters_(vcFile_prm, P, S_shank)
% ouput
% -----
% S_shank: {cviSpk_shank, cviSite_shank, csFile_spk_shank, csFile_fet_shank}
%   csFile_spk_shank: output file names to store spike waveforms by shank
%   csFile_fet_shank: output file names to store spike features by shank
%   cviSite_shank: site numbers per shank

if nargin<2, P = []; end
if nargin<3, S_shank = []; end

NUM_PC = 3;

fprintf('Exporting waveforms and features for all shanks\n\t'); t_spk = tic;
    
% [S0, P] = load_cached_(vcFile_prm);
% if isempty(P), P = P; end

[nPad_filt, nChans, vcDataType] = deal(P.nPad_filt, P.nChans, P.vcDataType);
vcFile_wav = strrep(P.vcFile_prm, '.prm', '_wav.jrc');
fid_w = [];

% plan loading
[fid1, nBytes_file, header_offset] = fopen_(P.vcFile, 'r');
[nLoad1, nSamples_load1, nSamples_last1] = plan_load_(nBytes_file, P);
nSamples_file = floor(nBytes_file / bytesPerSample_(vcDataType) / nChans);

% load files in steps with overlap
mnWav_pre1 = [];
iSample_file1 = 0; % zero base
v_fid_spk_shank = [];
cell_pv_shank = cell(size(S_shank.cviSite_shank));

for iLoad1 = 1:nLoad1
    nSamples1 = ifeq_(iLoad1 == nLoad1, nSamples_last1, nSamples_load1);
    mnWav1 = load_file_(fid1, nSamples1, P);
    if iLoad1 < nLoad1
        mnWav_post1 = load_file_preview_(fid1, P);
    else
        mnWav_post1 = [];
    end
    ilim_load1 = iSample_file1 + [1, nSamples1];
    [mnWav1, ilim_wav1] = filter_(mnWav1, mnWav_pre1, mnWav_post1, P);
    switch 2
        case 2 % save waveforms and fet, don't write the waveforms            
            if isempty(v_fid_spk_shank) % open files
                v_fid_spk_shank = cellfun(@(x)fopen(x, 'w'), S_shank.csFile_spk_shank, 'UniformOutput', 1);
                v_fid_fet_shank = cellfun(@(x)fopen(x, 'w'), S_shank.csFile_fet_shank, 'UniformOutput', 1);
            end
            % write to files
            for iShank = 1:numel(S_shank.cviSite_shank)       
                viTime_shank1 = S_shank.cviTime_spk_shank{iShank};
                viSite_shank1 = S_shank.cviSite_shank{iShank};
                [trWav11, viTime11] = mr2tr_sub_(mnWav1(:,viSite_shank1), ilim_wav1, ilim_load1, P.spkLim, viTime_shank1);
                trWav11 = meanSubt_(trWav11);
                if isempty(cell_pv_shank{iShank})
                    cell_pv_shank{iShank} = calc_pv_(trWav11, NUM_PC);
                end
                mnPc11 = calc_pc_(trWav11, cell_pv_shank{iShank}); % project feature
                
                % write waveform and compute waveform ranges and powers
                mrWav12 = reshape(permute(trWav11, [3,1,2]), [], size(trWav11,2)); % [nSites11, nSamples_spk, nSpk11]
                if ~strcmpi(class_(mrWav12), 'int16')
                    mrWav12 = int16(gather_(mrWav12) * get_set_(P, 'scale_filter', 200)); % make sure dynamic range is properly represented
                end
                fwrite(v_fid_spk_shank(iShank), mrWav12, 'int16'); % [nSites11, nSamples_spk, nSpk11]                
                vn_range11 = int64(range(mrWav12,1));
                vn_power11 = int64(sum(mrWav12.^2,1)/size(mrWav12,1)/100);                                
                clear mrWav12
                
                % save feature vector                                              
                mrFet11 = [mnPc11; vn_range11; vn_power11; int64(viTime11(:)'-1)];
                vcFormat = ['%d', repmat('\t%d', 1, size(mrFet11,1)-1), '\n'];
                if iLoad1 == 1
                    fprintf(v_fid_fet_shank(iShank), '%d\n', size(mrFet11,1));
                end
                fprintf(v_fid_fet_shank(iShank), vcFormat, mrFet11);
            end
            
        case 1 % save filtered waveforms to a file
            mnWav1 = mnWav1(ilim_wav1(1):ilim_wav1(end), :); % trim
            if isempty(fid_w), fid_w = fopen(vcFile_wav, 'w'); end
            fwrite_sub_(fid_w, gather_(mnWav1), iSample_file1, nSamples_file); % provide offset
    end
    % end
    if iLoad1 < nLoad1, mnWav_pre1 = mnWav1(end-P.nPad_filt+1:end, :); end
    clear mnWav1
    iSample_file1 = iSample_file1 + nSamples1;
    fprintf('.');
end %for
fprintf('\n');

% close files
fclose_(v_fid_spk_shank);
fclose_(v_fid_fet_shank);
fclose_(fid_w);
cellfun(@(x)fprintf('\tWrote to %s\n', x), S_shank.csFile_spk_shank);
cellfun(@(x)fprintf('\tWrote to %s\n', x), S_shank.csFile_fet_shank);
fprintf('\ttook %0.1fs\n', toc(t_spk));
end %func


%--------------------------------------------------------------------------
function trPv1 = calc_pv_(trWav1, nPc)
% trWav1: [nSamples_spk, nSpk1, nSites1]
% trPv1: [nSamples_spk, nPc, nSites1]

MAX_SAMPLE = 10000;

[nSamples_spk, nSpk1, nSites1] = size(trWav1);
trPv1 = zeros(nSamples_spk, nPc, nSites1, 'like', trWav1);
iMid = round(nSamples_spk/2);

viSpk_sub = subsample_vr_(1:size(trWav1,2), MAX_SAMPLE);
trWav2 = trWav1(:,viSpk_sub,:);

for iSite=1:nSites1
    mrWav11 = trWav2(:,:,iSite);
    [mrPv11, vrD11] = eig(mrWav11 * mrWav11');
    mrPv11 = zscore_(mrPv11(:,end:-1:end-nPc+1)); % sort largest first
    
    % spike center should be negative
%     vrSign11 = (median((mrPv11' * mrWav11)') > 0)*2-1;
    vrSign11 = (mrPv11(iMid,:) < 0) * 2 - 1; %1 or -1 depending on the sign
    trPv1(:,:,iSite) = bsxfun(@times, mrPv11, vrSign11);    
end %for
end %func


%--------------------------------------------------------------------------
function mnFet_spk1 = calc_pc_(trWav1, trPv)
% waveforms: int16
% capture three PCA
% trWav11: [nSamples_spk, nSpk11, nSites11]   
% trPv: [nSamples_spk, nPc, nSites11]

% constants
[~, nSpk1, nSites1] = size(trWav1);
[~, nPc, ~] = size(trPv);

trFet1 = zeros(nPc, nSpk1, nSites1, 'like', trWav1);
for iSite1 = 1:size(trPv,3)
    trFet1(:,:,iSite1) = trPv(:,:,iSite1)' * trWav1(:,:,iSite1); % [nPc, nSpk11]    
end
trFet1 = gather_(trFet1);
mnFet_spk1 = reshape(permute(trFet1, [1,3,2]), [], nSpk1); % [nPc, nSites, nSpk]
factor = (2^15)./max(abs(mnFet_spk1'));
mnFet_spk1 = int64(mnFet_spk1 .* factor');
end %func


%--------------------------------------------------------------------------
function [trWav_spk1, viTime_spk1] = mr2tr_sub_(mnWav1, ilim1, ilim_load1, spkLim, viTime_spk)
ilim_spk = [find(viTime_spk >= ilim_load1(1), 1, 'first'), find(viTime_spk <= ilim_load1(end), 1, 'last')];
viSpk1 = ilim_spk(1):ilim_spk(end);
viTime1 = viTime_spk(viSpk1) - ilim_load1(1) + ilim1(1);
trWav_spk1 = mr2tr_(mnWav1, spkLim, viTime1);
viTime_spk1 = viTime_spk(viSpk1);
end %func


%--------------------------------------------------------------------------
function [mnWav1, ilim_trim1] = filter_(mnWav_center1, mnWav_pre1, mnWav_post1, P)
[nPre1, nPost1] = deal(size(mnWav_pre1, 1), size(mnWav_post1, 1));
% mnWav1 = cat(1, mnWav_pre1, mnWav_center1, mnWav_post1);
mnWav1 = [mnWav_pre1; mnWav_center1; mnWav_post1];

% try filtering in GPU
fGpu = 0;
if fGpu
    try
        mnWav1 = filt_car_(single(gpuArray_(mnWav1)), P);
    catch
        fGpu = 0;
    end
end
if ~fGpu
    mnWav1 = filt_car_(single(mnWav1), P);
end
ilim_trim1 = [nPre1+1, size(mnWav1,1)-nPost1];
end %func


%--------------------------------------------------------------------------
function fwrite_sub_(fid_w, mnWav1, iSample_file1, nSamples_file)
% input
% -----
% mnWav1: nSamples1 x nChans
[nSamples1, nChans] = size(mnWav1);
nBytesPerSample1 = bytesPerSample_(mnWav1);
offset_pre = 0;
for iChan = 1:nChans
    offset1 = (nSamples_file * (iChan-1) + iSample_file1) * nBytesPerSample1;
    switch 2
        case 2, fseek(fid_w, offset1 - offset_pre, 'cof');
        case 1, fseek(fid_w, offset1, 'bof');
    end
    fwrite_(fid_w, mnWav1(:,iChan));
    offset_pre = offset1;
end
end %func


%--------------------------------------------------------------------------
% Call from irc2.m
function cell_out = call_irc2_(dbstack1, cell_input, nargout)
vcFunc = dbstack1(1).name;
try
    switch nargout
        case 0, cell_out{1} = []; irc2('call', vcFunc, cell_input);
        case 1, cell_out{1} = irc2('call', vcFunc, cell_input);
        case 2, [cell_out{1}, cell_out{2}] = irc2('call', vcFunc, cell_input);
        case 3, [cell_out{1}, cell_out{2}, cell_out{3}] = irc2('call', vcFunc, cell_input);
        case 4, [cell_out{1}, cell_out{2}, cell_out{3}, cell_out{4}] = irc2('call', vcFunc, cell_input);
        otherwise, error('call_irc2_: undefined func: %s', vcFunc);
    end
catch ME
    fprintf(2, 'call_irc2_: %s\n', ME.message);
    rethrow ME;
end
end %func


%--------------------------------------------------------------------------
% call irc
function varargout = load_fet_(varargin), cell_out = call_irc2_(dbstack(), varargin, nargout); varargout = cell_out; end
function varargout = exist_file_(varargin), cell_out = call_irc2_(dbstack(), varargin, nargout); varargout = cell_out; end
function varargout = get_(varargin), cell_out = call_irc2_(dbstack(), varargin, nargout); varargout = cell_out; end
function varargout = mkdir_(varargin), cell_out = call_irc2_(dbstack(), varargin, nargout); varargout = cell_out; end
function varargout = clu_wav_(varargin), cell_out = call_irc2_(dbstack(), varargin, nargout); varargout = cell_out; end
function varargout = mda2bin_(varargin), cell_out = call_irc2_(dbstack(), varargin, nargout); varargout = cell_out; end
function varargout = get_set_(varargin), cell_out = call_irc2_(dbstack(), varargin, nargout); varargout = cell_out; end
function varargout = vi2cell_(varargin), cell_out = call_irc2_(dbstack(), varargin, nargout); varargout = cell_out; end

function out1 = fwrite_(varargin), fn=dbstack(); out1 = irc('call', fn(1).name, varargin); end
function out1 = read_chan_(varargin), fn=dbstack(); out1 = irc('call', fn(1).name, varargin); end
function out1 = bytesPerSample_(varargin), fn=dbstack(); out1 = irc('call', fn(1).name, varargin); end
function out1 = load_file_(varargin), fn=dbstack(); out1 = irc('call', fn(1).name, varargin); end
function out1 = load_file_preview_(varargin), fn=dbstack(); out1 = irc('call', fn(1).name, varargin); end
function out1 = filt_car_(varargin), fn=dbstack(); out1 = irc('call', fn(1).name, varargin); end
function out1 = ifeq_(varargin), fn=dbstack(); out1 = irc('call', fn(1).name, varargin); end
function out1 = mr2tr_(varargin), fn=dbstack(); out1 = irc('call', fn(1).name, varargin); end
function out1 = fclose_(varargin), fn=dbstack(); out1 = irc('call', fn(1).name, varargin); end
function out1 = meanSubt_(varargin), fn=dbstack(); out1 = irc('call', fn(1).name, varargin); end
function out1 = zscore_(varargin), fn=dbstack(); out1 = irc('call', fn(1).name, varargin); end
function out1 = gpuArray_(varargin), fn=dbstack(); out1 = irc('call', fn(1).name, varargin); end
function out1 = gather_(varargin), fn=dbstack(); out1 = irc('call', fn(1).name, varargin); end
function out1 = subsample_vr_(varargin), fn=dbstack(); out1 = irc('call', fn(1).name, varargin); end
function out1 = class_(varargin), fn=dbstack(); out1 = irc('call', fn(1).name, varargin); end
function [out1, out2, out3] = fopen_(varargin), fn=dbstack(); [out1, out2, out3] = irc('call', fn(1).name, varargin); end
function [out1, out2, out3] = plan_load_(varargin), fn=dbstack(); [out1, out2, out3] = irc('call', fn(1).name, varargin); end
