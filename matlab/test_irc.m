


% srun matlab -nosplash -nodisplay -r "addpath('/mnt/home/magland/src/ironclust/'); 
%addpath('./matlab'); 
%addpath('./mdaio'); 
if ispc()
    p_ironclust('D:\mountainsort\out\', ...
        'D:\mountainsort\raw.mda', ...
        'D:\mountainsort\geom.csv', ...
        'tetrode_template.prm', ...
        'D:\mountainsort\firings_true.mda', ...
        'D:\mountainsort\firings_out.mda', ...
        'D:\mountainsort\argfile.txt'); 
end