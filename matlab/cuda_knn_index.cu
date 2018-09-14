/* 
 * James Jun 2018/7/3 
 * Fast approximation of knn using binned minimum parallel search
 * J. James Jun, Flatiron Institute, 2018 July 5
*/

#include <cuda_runtime.h>
#include <math.h>
#define ABS(my_val) ((my_val) < 0) ? -(my_val) : (my_val)
#define NC (2*18) //2pca x 18 channels max
#define CHUNK (8)
#define SINGLE_INF (3.402E+38) // equipvalent to NAN. consider -1 value
#define NTHREADS (256)
#define SWAP(x, y, T) do { T SWAP = x; x = y; y = SWAP; } while (0)

/** Main entry point.
 * Works out where the current thread should read/write to global memory
 * and calls doIterations to do the actual work.
 * K: K nearest neighbor
 * I: Index (knn x nA)
 * F: Feature matrix (nC x *)
 * viB: Index B (nB x 1)
 * viA: Index A (nA x 1)
 */
__global__ void cuda_knn_index(float *K, int *I, float const *B, float const *A, const int *vnConst){
    
    int nB = vnConst[0];
    int nA = vnConst[1];
    int nC = vnConst[2];
    int knn = vnConst[3]; // not used for now

    int tx = threadIdx.x;
    int iA = (blockIdx.x + blockIdx.y * gridDim.x) * CHUNK + tx;
    //int iB = threadIdx.x;    
    int nThreads = blockDim.x; // must be less than NTHREADS

    __shared__ float sA[NC][CHUNK];
    __shared__ float sD[NTHREADS][CHUNK];
    __shared__ int sI[NTHREADS][CHUNK];
    
    // initialize
    if (tx < CHUNK){        
        if (iA < nA){
            int iA_ = tx;
            for (int iC=0; iC<nC; ++iC) sA[iC][iA_] = A[iC + iA*nC]; // copy A->sA   
            for (int iT=0; iT<nThreads; ++iT){
                sD[iT][iA_] = SINGLE_INF; // sD = inf
                sI[iT][iA_] = 0;
            }
        }
    }
    __syncthreads();
    
    
    // find minimum for each bin
    for (int iB=tx; iB<nB; iB+=nThreads){
        int iB_ = tx;
        float dist_[CHUNK];
        for (int iA_=0; iA_<CHUNK; ++iA_) dist_[iA_] = 0.0f;
        for (int iC=0; iC<nC; ++iC){
            float b_ = B[iC + iB*nC];
            for (int iA_=0; iA_<CHUNK; ++iA_){
                float d_ = b_ - sA[iC][iA_];
                dist_[iA_] += (d_ * d_);
            }            
        }          
        for (int iA_=0; iA_<CHUNK; ++iA_){
            if (dist_[iA_] < sD[iB_][iA_]){
                sD[iB_][iA_] = dist_[iA_];
                sI[iB_][iA_] = iB;
            }
        }
    } // while
    __syncthreads();
    
    
    // sort up to kth element using bubble sort
    if (tx < CHUNK){           
        if (iA < nA){
            int iA_ = tx;
            for (int iK=0; iK<knn; ++iK){
                float dmin_ = sD[iK][iA_];
                int imin_ = iK;
                for (int iB_=iK; iB_<nThreads; ++iB_){
                    float d_ = sD[iB_][iA_];
                    if (d_ < dmin_){
                        dmin_ = d_;
                        imin_ = iB_;
                    }
                }
                SWAP(sD[imin_][iA_], sD[iK][iA_], float);
                SWAP(sI[imin_][iA_], sI[iK][iA_], int);
                /*sD[imin_][iA_] = sD[iK][iA_];
                sD[iK][iA_] = dmin_;
                sI[imin_][iA_] = sI[iK][iA_];
                sI[iK][iA_] = imin_;*/
            }      
            // average or take the last?
            K[iA] = sqrt(ABS(sD[knn-1][iA_]));
            //float k_ave = 0.0;
            for (int iK=0; iK<knn; ++iK){
                I[iK + knn*iA] = sI[iK][iA_] + 1; // matlab 1 base
                //k_ave += sD[iK][iA_];
            }
            //k_ave /= knn;
            //K[iA] = sqrt(ABS(k_ave));
        }        
    } // if
} // func
