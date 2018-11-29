function run_irc(vcDir_in, vcDir_out, vcFile_template)
% usage
% -----
% run_irc(command)
% run_irc(vcDir_in, vcDir_out, vcFile_template)
%
% arguments
% -----
% vcDir_in: input directory
% vcDir_out: output directory
% vcFile_template: template file (optional)

if nargin<3, vcFile_template = ''; end

if ~isdeployed()
    source_path = fileparts(mfilename('fullpath'));
    addpath(genpath(fullfile(source_path, '/matlab'))); 
end
if nargin==1
    vcCmd = vcDir_in;
    fprintf('%s\n', irc(vcCmd)); 
    return; 
end

    
cSep = filesep();

p_ironclust(vcDir_out, ...
  [vcDir_in, cSep, 'raw.mda'], ...
  [vcDir_in, cSep, 'geom.csv'], ...
  vcFile_template, ...
  [vcDir_in, cSep, 'firings_true.mda'], ...
  [vcDir_out, cSep, 'firings_out.mda'], ...
  [vcDir_in, cSep, 'params.json']);

try
    if isdeployed() || ismcc(), exit(); end
catch
    ;
end

end %func