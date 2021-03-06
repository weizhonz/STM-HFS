function [x, funVal, ValueL]=tree_LeastR(A, y, z, opts)
%
%%
% Function tree_LeastR
%      Least Squares Loss with the 
%           tree structured group Lasso Regularization
%
%% Problem
%
%  min  1/2 || A x - y||^2 + z * sum_j w_j ||x_{G_j}||
%
%  G_j's are nodes with tree structure
%
%  The tree overlapping group information is contained in
%  opts.ind, which is a 3 x nodes matrix, where nodes denotes the number of
%  nodes of the tree.
%
%  opts.ind(1,:) contains the starting index
%  opts.ind(2,:) contains the ending index
%  opts.ind(3,:) contains the corresponding weight (w_j)
%
%  Note: 
%  1) If each element of x is a leaf node of the tree and the weight for
%  this leaf node are the same, we provide an alternative "efficient" input
%  for this kind of node, by creating a "super node" with 
%  opts.ind(1,1)=-1; opts.ind(2,1)=-1; and opts.ind(3,1)=the common weight.
%
%  2) If the features are well ordered in that, the features of the left
%  tree is always less than those of the right tree, opts.ind(1,:) and
%  opts.ind(2,:) contain the "real" starting and ending indices. That is to
%  say, x( opts.ind(1,j):opts.ind(2,j) ) denotes x_{G_j}. In this case,
%  the entries in opts.ind(1:2,:) are within 1 and n.
%
%
%  If the features are not well ordered, please use the input opts.G for
%  specifying the index so that  
%   x( opts.G ( opts.ind(1,j):opts.ind(2,j) ) ) denotes x_{G_j}.
%  In this case, the entries of opts.G are within 1 and n, and the entries of
%  opts.ind(1:2,:) are within 1 and length(opts.G).
%
% The following example shows how G and ind works:
%
% G={ {1, 2}, {4, 5}, {3, 6}, {7, 8},
%     {1, 2, 3, 6}, {4, 5, 7, 8}, 
%     {1, 2, 3, 4, 5, 6, 7, 8} }.
%
% ind={ [1, 2, 100]', [3, 4, 100]', [5, 6, 100]', [7, 8, 100]',
%       [9, 12, 100]', [13, 16, 100]', [17, 24, 100]' },
%
% where each node has a weight of 100.
%
%
%% Input parameters:
%
%  A-         Matrix of size m x n
%                A can be a dense matrix
%                         a sparse matrix
%                         or a DCT matrix
%  y -        Response vector (of size mx1)
%  z -        Tree Structure regularization parameter (z >=0)
%  opts-      optional inputs (default value: opts=[])
%
%% Output parameters:
%
%  x-         Solution
%  funVal-    Function value during iterations
%
%% Copyright (C) 2010-2011 Jun Liu, and Jieping Ye
%
% You are suggested to first read the Manual.
%
% For any problem, please contact with Jun Liu via j.liu@asu.edu
%
% Last modified on October 3, 2010.
%
%% Related papers
%
% [1] Jun Liu and Jieping Ye, Moreau-Yosida Regularization for 
%     Grouped Tree Structure Learning, NIPS 2010
%
%% Related functions:
%
%  sll_opts
%
%%

%% Verify and initialize the parameters
%%
if (nargin <4)
    error('\n Inputs: A, y, z, and opts.ind should be specified!\n');
end

[m,n]=size(A);

if (length(y) ~=m)
    error('\n Check the length of y!\n');
end

if (z<0)
    error('\n z should be nonnegative!\n');
end

opts=sll_opts(opts); % run sll_opts to set default values (flags)

% restart the program for better efficiency
%  this is a newly added function
if (~isfield(opts,'rStartNum'))
    opts.rStartNum=opts.maxIter;
else
    if (opts.rStartNum<=0)
        opts.rStartNum=opts.maxIter;
    end
end

%% Detailed initialization
%% Normalization

% Please refer to sll_opts for the definitions of mu, nu and nFlag
%
% If .nFlag =1, the input matrix A is normalized to
%                     A= ( A- repmat(mu, m,1) ) * diag(nu)^{-1}
%
% If .nFlag =2, the input matrix A is normalized to
%                     A= diag(nu)^{-1} * ( A- repmat(mu, m,1) )
%
% Such normalization is done implicitly
%     This implicit normalization is suggested for the sparse matrix
%                                    but not for the dense matrix
%

if (opts.nFlag~=0)
    if (isfield(opts,'mu'))
        mu=opts.mu;
        if(size(mu,2)~=n)
            error('\n Check the input .mu');
        end
    else
        mu=mean(A,1);
    end
    
    if (opts.nFlag==1)
        if (isfield(opts,'nu'))
            nu=opts.nu;
            if(size(nu,1)~=n)
                error('\n Check the input .nu!');
            end
        else
            nu=(sum(A.^2,1)/m).^(0.5); nu=nu';
        end
    else % .nFlag=2
        if (isfield(opts,'nu'))
            nu=opts.nu;
            if(size(nu,1)~=m)
                error('\n Check the input .nu!');
            end
        else
            nu=(sum(A.^2,2)/n).^(0.5);
        end
    end
    
    ind_zero=find(abs(nu)<= 1e-10);    nu(ind_zero)=1;
    % If some values in nu is typically small, it might be that,
    % the entries in a given row or column in A are all close to zero.
    % For numerical stability, we set the corresponding value to 1.
end

if (~issparse(A)) && (opts.nFlag~=0)
    fprintf('\n -----------------------------------------------------');
    fprintf('\n The data is not sparse or not stored in sparse format');
    fprintf('\n The code still works.');
    fprintf('\n But we suggest you to normalize the data directly,');
    fprintf('\n for achieving better efficiency.');
    fprintf('\n -----------------------------------------------------');
end

%% Group & Others 

% Initialize ind 
if (~isfield(opts,'ind'))
    error('\n In tree_LeastR, the field .ind should be specified');
else
    ind=opts.ind;
   
    if (size(ind,1)~=3)
        error('\n Check opts.ind');
    end
end

GFlag=0;
% if GFlag=1, we shall apply general_altra
if (isfield(opts,'G'))
    GFlag=1;
    
    G=opts.G;
    if (max(G) >n || max(G) <1)
        error('\n The input G is incorrect. It should be within %d and %d',1,n);
    end
end

%% Starting point initialization

% compute AT y
if (opts.nFlag==0)
    ATy =A'*y;
elseif (opts.nFlag==1)
    ATy= A'*y - sum(y) * mu';  ATy=ATy./nu;
else
    invNu=y./nu;              ATy=A'*invNu-sum(invNu)*mu';
end

% process the regularization parameter
if (opts.rFlag==0)
    lambda=z;
else % z here is the scaling factor lying in [0,1]
%     if (z<0 || z>1)
%         error('\n opts.rFlag=1, and z should be in [0,1]');
%     end
    
    computedFlag=0;
    if (isfield(opts,'lambdaMax'))
        if (opts.lambdaMax~=-1)
            lambda=z*opts.lambdaMax;
            computedFlag=1;
        end
    end
    
    if (~computedFlag)        
        if (GFlag==0)
            lambda_max=findLambdaMax(ATy, n, ind, size(ind,2));
        else
            lambda_max=general_findLambdaMax(ATy, n, G, ind, size(ind,2));
        end
        
        % As .rFlag=1, we set lambda as a ratio of lambda_max
        lambda=z*lambda_max;
    end
end


% The following is for computing lambdaMax
% we use opts.lambdaMax=-1 to show that we need the computation.
% 
% One can use this for setting up opts.lambdaMax
if (isfield(opts,'lambdaMax'))
    
    if (opts.lambdaMax==-1)
        if (GFlag==0)
            lambda_max=findLambdaMax(ATy, n, ind, size(ind,2));
        else
            lambda_max=general_findLambdaMax(ATy, n, G, ind, size(ind,2));
        end
        
        x=lambda_max;
        funVal=lambda_max;
        ValueL=lambda_max;
        
        return;
    end
end


% initialize a starting point
if opts.init==2
    x=zeros(n,1);
else
    if isfield(opts,'x0')
        x=opts.x0;
        if (length(x)~=n)
            error('\n Check the input .x0');
        end
    else
        x=ATy;  % if .x0 is not specified, we use ratio*ATy,
        % where ratio is a positive value
    end
end

% compute A x
if (opts.nFlag==0)
    Ax=A* x;
elseif (opts.nFlag==1)
    invNu=x./nu; mu_invNu=mu * invNu;
    Ax=A*invNu -repmat(mu_invNu, m, 1);
else
    Ax=A*x-repmat(mu*x, m, 1);     Ax=Ax./nu;
end

if (opts.init==0) 
    % ------  This function is not available
    %
    % If .init=0, we set x=ratio*x by "initFactor"
    % Please refer to the function initFactor for detail
    %
    
    % Here, we only support starting from zero, due to the complex tree
    % structure
    
    x=zeros(n,1);    
end

%% The main program
% The Armijo Goldstein line search schemes + accelearted gradient descent

bFlag=0; % this flag tests whether the gradient step only changes a little

if (opts.mFlag==0 && opts.lFlag==0)    
    L=1;
    % We assume that the maximum eigenvalue of A'A is over 1
    
    % assign xp with x, and Axp with Ax
    xp=x; Axp=Ax; xxp=zeros(n,1);
    
    alphap=0; alpha=1;
    
    for iterStep=1:opts.maxIter
        % --------------------------- step 1 ---------------------------
        % compute search point s based on xp and x (with beta)
        beta=(alphap-1)/alpha;    s=x + beta* xxp;
        
        % --------------------------- step 2 ---------------------------
        % line search for L and compute the new approximate solution x
        
        % compute the gradient (g) at s
        As=Ax + beta* (Ax-Axp);
        
        % compute AT As
        if (opts.nFlag==0)
            ATAs=A'*As;
        elseif (opts.nFlag==1)
            ATAs=A'*As - sum(As) * mu';  ATAs=ATAs./nu;
        else
            invNu=As./nu;                ATAs=A'*invNu-sum(invNu)*mu';
        end
        
        % obtain the gradient g
        g=ATAs-ATy;
        
        % copy x and Ax to xp and Axp
        xp=x;    Axp=Ax;
        
        while (1)
            % let s walk in a step in the antigradient of s to get v
            % and then do the L1/Lq-norm regularized projection
            v=s-g/L;
            
            % tree overlapping group Lasso projection
            ind_work(1:2,:)=ind(1:2,:);
            ind_work(3,:)=ind(3,:) * (lambda / L);
            
            if (GFlag==0)
                x=altra(v, n, ind_work, size(ind_work,2));
            else
                x=general_altra(v, n, G, ind_work, size(ind_work,2));
            end
            
            v=x-s;  % the difference between the new approximate solution x
            % and the search point s
            
            % compute A x
            if (opts.nFlag==0)
                Ax=A* x;
            elseif (opts.nFlag==1)
                invNu=x./nu; mu_invNu=mu * invNu;
                Ax=A*invNu -repmat(mu_invNu, m, 1);
            else
                Ax=A*x-repmat(mu*x, m, 1);     Ax=Ax./nu;
            end
            
            Av=Ax -As;
            r_sum=v'*v; l_sum=Av'*Av;
            
            if (r_sum <=1e-20)
                bFlag=1; % this shows that, the gradient step makes little improvement
                break;
            end
            
            % the condition is ||Av||_2^2 <= L * ||v||_2^2
            if(l_sum <= r_sum * L)
                break;
            else
                L=max(2*L, l_sum/r_sum);
                %fprintf('\n L=%5.6f',L);
            end
        end
        
        % --------------------------- step 3 ---------------------------
        % update alpha and alphap, and check whether converge
        alphap=alpha; alpha= (1+ sqrt(4*alpha*alpha +1))/2;
        
        xxp=x-xp;   Axy=Ax-y;
        
        ValueL(iterStep)=L;
                
        % compute the regularization part     
        if (GFlag==0)
            tree_norm=treeNorm(x, n, ind, size(ind,2));
        else
            tree_norm=general_treeNorm(x, n, G, ind, size(ind,2));
        end
        
        % function value = loss + regularizatioin
        funVal(iterStep)=Axy'* Axy/2 + lambda * tree_norm;
        
        if (bFlag)
            % fprintf('\n The program terminates as the gradient step changes the solution very small.');
            break;
        end
        
        switch(opts.tFlag)
            case 0
                if iterStep>=2
                    if (abs( funVal(iterStep) - funVal(iterStep-1) ) <= opts.tol)
                        break;
                    end
                end
            case 1
                if iterStep>=2
                    if (abs( funVal(iterStep) - funVal(iterStep-1) ) <=...
                            opts.tol* funVal(iterStep-1))
                        break;
                    end
                end
            case 2
                if ( funVal(iterStep)<= opts.tol)
                    break;
                end
            case 3
                norm_xxp=sqrt(xxp'*xxp);
                if ( norm_xxp <=opts.tol)
                    break;
                end
            case 4
                norm_xp=sqrt(xp'*xp);    norm_xxp=sqrt(xxp'*xxp);
                if ( norm_xxp <=opts.tol * max(norm_xp,1))
                    break;
                end
            case 5
                if iterStep>=opts.maxIter
                    break;
                end
        end
        
        % restart the program every opts.rStartNum
        if (~mod(iterStep, opts.rStartNum))
            alphap=0; alpha=1;
            xp=x; Axp=Ax; xxp=zeros(n,1); L =L/2;
        end
    end    
else
    error('\n The function does not support opts.mFlag neq 0 & opts.lFlag neq 0!');
end