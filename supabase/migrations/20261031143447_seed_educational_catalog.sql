-- Educational mock catalog. No real user or resume records.
-- Sources are versioned; embeddings remain pending until the n8n indexing stage.
INSERT INTO public.companies(company_id,name) VALUES ('amazon','Amazon');
INSERT INTO public.companies(company_id,name) VALUES ('deloitte','Deloitte');
INSERT INTO public.companies(company_id,name) VALUES ('google','Google');
INSERT INTO public.companies(company_id,name) VALUES ('microsoft','Microsoft');
INSERT INTO public.companies(company_id,name) VALUES ('nvidia','NVIDIA');
INSERT INTO public.internship_roles(role_id,company_id,role_title,location,stipend_inr_month,deadline,required_skills,preferred_skills) VALUES ('AMAZON-01','amazon','SDE Intern','Hyderabad',60000,'2026-12-15',ARRAY['Java or Python or C++','data structures','algorithms','OOP','Git']::text[],ARRAY['AWS','SQL','REST APIs','Linux']::text[]);
INSERT INTO public.internship_roles(role_id,company_id,role_title,location,stipend_inr_month,deadline,required_skills,preferred_skills) VALUES ('AMAZON-02','amazon','Cloud Support Intern','Hyderabad',45000,'2026-12-18',ARRAY['Linux','networking basics','cloud fundamentals','troubleshooting','scripting']::text[],ARRAY['AWS EC2/S3/IAM','Python','monitoring','SQL']::text[]);
INSERT INTO public.internship_roles(role_id,company_id,role_title,location,stipend_inr_month,deadline,required_skills,preferred_skills) VALUES ('AMAZON-03','amazon','Data Analyst Intern','Bengaluru',40000,'2026-12-22',ARRAY['SQL','Excel','Python','data cleaning','statistics','dashboards']::text[],ARRAY['Pandas','QuickSight','AWS Athena','A/B testing']::text[]);
INSERT INTO public.internship_roles(role_id,company_id,role_title,location,stipend_inr_month,deadline,required_skills,preferred_skills) VALUES ('MICROSOFT-01','microsoft','Software Engineering Intern','Hyderabad',75000,'2026-12-20',ARRAY['C++ or C# or Java or Python','DSA','OOP','SQL','software fundamentals']::text[],ARRAY['Azure','GitHub','REST APIs','unit testing','CI/CD']::text[]);
INSERT INTO public.internship_roles(role_id,company_id,role_title,location,stipend_inr_month,deadline,required_skills,preferred_skills) VALUES ('MICROSOFT-02','microsoft','Azure Cloud Intern','Hyderabad',60000,'2026-12-23',ARRAY['Cloud fundamentals','networking','Linux or Windows administration','scripting','security basics']::text[],ARRAY['Azure services','PowerShell','Terraform','Docker','monitoring']::text[]);
INSERT INTO public.internship_roles(role_id,company_id,role_title,location,stipend_inr_month,deadline,required_skills,preferred_skills) VALUES ('MICROSOFT-03','microsoft','AI Engineering Intern','Bengaluru',70000,'2026-12-28',ARRAY['Python','ML fundamentals','data preprocessing','PyTorch or TensorFlow','model evaluation']::text[],ARRAY['Azure AI','NLP','transformers','MLOps','Docker']::text[]);
INSERT INTO public.internship_roles(role_id,company_id,role_title,location,stipend_inr_month,deadline,required_skills,preferred_skills) VALUES ('GOOGLE-01','google','Data Science Intern','Bengaluru',70000,'2026-12-10',ARRAY['Python','Pandas','NumPy','SQL','statistics','visualization','ML basics']::text[],ARRAY['Scikit-learn','BigQuery','TensorFlow','A/B testing']::text[]);
INSERT INTO public.internship_roles(role_id,company_id,role_title,location,stipend_inr_month,deadline,required_skills,preferred_skills) VALUES ('GOOGLE-02','google','Software Engineering Intern','Bengaluru',80000,'2026-12-16',ARRAY['Python or Java or C++','DSA','OOP','debugging','Git']::text[],ARRAY['Distributed systems','testing','Linux','databases','APIs']::text[]);
INSERT INTO public.internship_roles(role_id,company_id,role_title,location,stipend_inr_month,deadline,required_skills,preferred_skills) VALUES ('GOOGLE-03','google','Cloud Engineering Intern','Hyderabad',65000,'2026-12-21',ARRAY['Cloud concepts','Linux','networking','Python','containers','Git']::text[],ARRAY['Google Cloud','Kubernetes','Terraform','CI/CD','observability']::text[]);
INSERT INTO public.internship_roles(role_id,company_id,role_title,location,stipend_inr_month,deadline,required_skills,preferred_skills) VALUES ('NVIDIA-01','nvidia','AI/ML Intern','Bengaluru',65000,'2026-12-25',ARRAY['Python','machine learning','deep learning','PyTorch or TensorFlow','NumPy','evaluation']::text[],ARRAY['CUDA','C++','computer vision','transformers','GPU acceleration']::text[]);
INSERT INTO public.internship_roles(role_id,company_id,role_title,location,stipend_inr_month,deadline,required_skills,preferred_skills) VALUES ('NVIDIA-02','nvidia','Computer Vision Intern','Bengaluru',70000,'2026-12-27',ARRAY['Python','OpenCV','image processing','CNNs','PyTorch','evaluation metrics']::text[],ARRAY['Object detection','segmentation','CUDA','ONNX','deployment']::text[]);
INSERT INTO public.internship_roles(role_id,company_id,role_title,location,stipend_inr_month,deadline,required_skills,preferred_skills) VALUES ('NVIDIA-03','nvidia','Deep Learning Intern','Bengaluru',75000,'2026-12-30',ARRAY['Python','neural networks','backpropagation','PyTorch','experiment tracking','statistics']::text[],ARRAY['Transformers','distributed training','CUDA','optimization','MLOps']::text[]);
INSERT INTO public.internship_roles(role_id,company_id,role_title,location,stipend_inr_month,deadline,required_skills,preferred_skills) VALUES ('DELOITTE-01','deloitte','Data Analyst Intern','Hyderabad',25000,'2026-12-05',ARRAY['Excel','SQL','Python basics','data cleaning','visualization','analytical reasoning']::text[],ARRAY['Power BI','Tableau','Pandas','business analytics']::text[]);
INSERT INTO public.internship_roles(role_id,company_id,role_title,location,stipend_inr_month,deadline,required_skills,preferred_skills) VALUES ('DELOITTE-02','deloitte','Technology Consulting Intern','Hyderabad',30000,'2026-12-12',ARRAY['Business analysis','communication','Excel','SQL','requirements gathering','documentation']::text[],ARRAY['Python','cloud basics','process mapping','Agile','Power BI']::text[]);
INSERT INTO public.internship_roles(role_id,company_id,role_title,location,stipend_inr_month,deadline,required_skills,preferred_skills) VALUES ('DELOITTE-03','deloitte','Cybersecurity Intern','Hyderabad',35000,'2026-12-19',ARRAY['Networking','Linux','security fundamentals','log analysis','incident response basics']::text[],ARRAY['SIEM','Python','OWASP','cloud security','vulnerability assessment']::text[]);
INSERT INTO public.role_documents(document_key,source_version,company_id,source_title,content) VALUES ('amazon_internships',1,'amazon','Amazon Internship Roles','# Amazon | Simulated internship listings

EDUCATIONAL MOCK DATA ONLY. Not real vacancies.

## 1. SDE Intern
Role ID: AMAZON-01
Company: Amazon
Location: Hyderabad, India
Duration: 3 months (simulated)
Stipend: INR 60,000/month (simulated)
Deadline: 2026-12-15 (simulated)
Eligibility: B.Tech students in relevant computing disciplines (simulated).
Required skills: Java or Python or C++; data structures; algorithms; OOP; Git
Preferred skills: AWS; SQL; REST APIs; Linux
Responsibilities: Develop and test backend features; debug services; write unit tests; review code
Relevant resume evidence: Backend API, algorithms or software engineering projects
Evaluation: Only cite resume-supported evidence; no protected-trait scoring.

## 2. Cloud Support Intern
Role ID: AMAZON-02
Company: Amazon
Location: Hyderabad, India
Duration: 3 months (simulated)
Stipend: INR 45,000/month (simulated)
Deadline: 2026-12-18 (simulated)
Eligibility: B.Tech students in relevant computing disciplines (simulated).
Required skills: Linux; networking basics; cloud fundamentals; troubleshooting; scripting
Preferred skills: AWS EC2/S3/IAM; Python; monitoring; SQL
Responsibilities: Investigate cloud incidents; troubleshoot deployment issues; document fixes; assist infrastructure teams
Relevant resume evidence: Cloud deployment, infrastructure automation or Linux projects
Evaluation: Only cite resume-supported evidence; no protected-trait scoring.

## 3. Data Analyst Intern
Role ID: AMAZON-03
Company: Amazon
Location: Bengaluru, India
Duration: 3 months (simulated)
Stipend: INR 40,000/month (simulated)
Deadline: 2026-12-22 (simulated)
Eligibility: B.Tech students in relevant computing disciplines (simulated).
Required skills: SQL; Excel; Python; data cleaning; statistics; dashboards
Preferred skills: Pandas; QuickSight; AWS Athena; A/B testing
Responsibilities: Analyze operational metrics; prepare reports; validate datasets; communicate insights
Relevant resume evidence: SQL analytics, dashboard or business data projects
Evaluation: Only cite resume-supported evidence; no protected-trait scoring.');
INSERT INTO public.role_documents(document_key,source_version,company_id,source_title,content) VALUES ('deloitte_internships',1,'deloitte','Deloitte Internship Roles','# Deloitte | Simulated internship listings

EDUCATIONAL MOCK DATA ONLY. Not real vacancies.

## 1. Data Analyst Intern
Role ID: DELOITTE-01
Company: Deloitte
Location: Hyderabad, India
Duration: 3 months (simulated)
Stipend: INR 25,000/month (simulated)
Deadline: 2026-12-05 (simulated)
Eligibility: B.Tech students in relevant computing disciplines (simulated).
Required skills: Excel; SQL; Python basics; data cleaning; visualization; analytical reasoning
Preferred skills: Power BI; Tableau; Pandas; business analytics
Responsibilities: Analyze client data; create dashboards; identify trends; summarize insights
Relevant resume evidence: Business intelligence, SQL or exploratory data analysis projects
Evaluation: Only cite resume-supported evidence; no protected-trait scoring.

## 2. Technology Consulting Intern
Role ID: DELOITTE-02
Company: Deloitte
Location: Hyderabad, India
Duration: 3 months (simulated)
Stipend: INR 30,000/month (simulated)
Deadline: 2026-12-12 (simulated)
Eligibility: B.Tech students in relevant computing disciplines (simulated).
Required skills: Business analysis; communication; Excel; SQL; requirements gathering; documentation
Preferred skills: Python; cloud basics; process mapping; Agile; Power BI
Responsibilities: Gather requirements; map processes; support technical recommendations; prepare client-ready deliverables
Relevant resume evidence: Process automation, product requirements or analytics projects
Evaluation: Only cite resume-supported evidence; no protected-trait scoring.

## 3. Cybersecurity Intern
Role ID: DELOITTE-03
Company: Deloitte
Location: Hyderabad, India
Duration: 3 months (simulated)
Stipend: INR 35,000/month (simulated)
Deadline: 2026-12-19 (simulated)
Eligibility: B.Tech students in relevant computing disciplines (simulated).
Required skills: Networking; Linux; security fundamentals; log analysis; incident response basics
Preferred skills: SIEM; Python; OWASP; cloud security; vulnerability assessment
Responsibilities: Review security alerts; document risks; analyze logs; assist assessment teams
Relevant resume evidence: Security monitoring, log analytics or web security projects
Evaluation: Only cite resume-supported evidence; no protected-trait scoring.');
INSERT INTO public.role_documents(document_key,source_version,company_id,source_title,content) VALUES ('google_internships',1,'google','Google Internship Roles','# Google | Simulated internship listings

EDUCATIONAL MOCK DATA ONLY. Not real vacancies.

## 1. Data Science Intern
Role ID: GOOGLE-01
Company: Google
Location: Bengaluru, India
Duration: 3 months (simulated)
Stipend: INR 70,000/month (simulated)
Deadline: 2026-12-10 (simulated)
Eligibility: B.Tech students in relevant computing disciplines (simulated).
Required skills: Python; Pandas; NumPy; SQL; statistics; visualization; ML basics
Preferred skills: Scikit-learn; BigQuery; TensorFlow; A/B testing
Responsibilities: Explore datasets; build predictive baselines; present findings; validate analysis
Relevant resume evidence: Predictive modeling, research or analytics dashboard projects
Evaluation: Only cite resume-supported evidence; no protected-trait scoring.

## 2. Software Engineering Intern
Role ID: GOOGLE-02
Company: Google
Location: Bengaluru, India
Duration: 3 months (simulated)
Stipend: INR 80,000/month (simulated)
Deadline: 2026-12-16 (simulated)
Eligibility: B.Tech students in relevant computing disciplines (simulated).
Required skills: Python or Java or C++; DSA; OOP; debugging; Git
Preferred skills: Distributed systems; testing; Linux; databases; APIs
Responsibilities: Build reliable services; test code; investigate bugs; collaborate on design
Relevant resume evidence: Backend, systems or algorithmic projects
Evaluation: Only cite resume-supported evidence; no protected-trait scoring.

## 3. Cloud Engineering Intern
Role ID: GOOGLE-03
Company: Google
Location: Hyderabad, India
Duration: 3 months (simulated)
Stipend: INR 65,000/month (simulated)
Deadline: 2026-12-21 (simulated)
Eligibility: B.Tech students in relevant computing disciplines (simulated).
Required skills: Cloud concepts; Linux; networking; Python; containers; Git
Preferred skills: Google Cloud; Kubernetes; Terraform; CI/CD; observability
Responsibilities: Prototype cloud solutions; configure deployments; monitor performance; troubleshoot
Relevant resume evidence: Containerized application, Kubernetes or cloud automation projects
Evaluation: Only cite resume-supported evidence; no protected-trait scoring.');
INSERT INTO public.role_documents(document_key,source_version,company_id,source_title,content) VALUES ('microsoft_internships',1,'microsoft','Microsoft Internship Roles','# Microsoft | Simulated internship listings

EDUCATIONAL MOCK DATA ONLY. Not real vacancies.

## 1. Software Engineering Intern
Role ID: MICROSOFT-01
Company: Microsoft
Location: Hyderabad, India
Duration: 3 months (simulated)
Stipend: INR 75,000/month (simulated)
Deadline: 2026-12-20 (simulated)
Eligibility: B.Tech students in relevant computing disciplines (simulated).
Required skills: C++ or C# or Java or Python; DSA; OOP; SQL; software fundamentals
Preferred skills: Azure; GitHub; REST APIs; unit testing; CI/CD
Responsibilities: Implement features; write tests; fix defects; maintain documentation
Relevant resume evidence: Full-stack, developer tooling or cloud application projects
Evaluation: Only cite resume-supported evidence; no protected-trait scoring.

## 2. Azure Cloud Intern
Role ID: MICROSOFT-02
Company: Microsoft
Location: Hyderabad, India
Duration: 3 months (simulated)
Stipend: INR 60,000/month (simulated)
Deadline: 2026-12-23 (simulated)
Eligibility: B.Tech students in relevant computing disciplines (simulated).
Required skills: Cloud fundamentals; networking; Linux or Windows administration; scripting; security basics
Preferred skills: Azure services; PowerShell; Terraform; Docker; monitoring
Responsibilities: Deploy test environments; investigate cloud reliability; automate operational tasks
Relevant resume evidence: Cloud deployment, monitoring or infrastructure projects
Evaluation: Only cite resume-supported evidence; no protected-trait scoring.

## 3. AI Engineering Intern
Role ID: MICROSOFT-03
Company: Microsoft
Location: Bengaluru, India
Duration: 3 months (simulated)
Stipend: INR 70,000/month (simulated)
Deadline: 2026-12-28 (simulated)
Eligibility: B.Tech students in relevant computing disciplines (simulated).
Required skills: Python; ML fundamentals; data preprocessing; PyTorch or TensorFlow; model evaluation
Preferred skills: Azure AI; NLP; transformers; MLOps; Docker
Responsibilities: Prototype AI features; evaluate models; analyze failure cases; document experiments
Relevant resume evidence: NLP, computer vision or deployed ML projects
Evaluation: Only cite resume-supported evidence; no protected-trait scoring.');
INSERT INTO public.role_documents(document_key,source_version,company_id,source_title,content) VALUES ('nvidia_internships',1,'nvidia','NVIDIA Internship Roles','# NVIDIA | Simulated internship listings

EDUCATIONAL MOCK DATA ONLY. Not real vacancies.

## 1. AI/ML Intern
Role ID: NVIDIA-01
Company: NVIDIA
Location: Bengaluru, India
Duration: 3 months (simulated)
Stipend: INR 65,000/month (simulated)
Deadline: 2026-12-25 (simulated)
Eligibility: B.Tech students in relevant computing disciplines (simulated).
Required skills: Python; machine learning; deep learning; PyTorch or TensorFlow; NumPy; evaluation
Preferred skills: CUDA; C++; computer vision; transformers; GPU acceleration
Responsibilities: Train and benchmark models; preprocess data; compare architectures; report results
Relevant resume evidence: Deep learning, vision or model optimization projects
Evaluation: Only cite resume-supported evidence; no protected-trait scoring.

## 2. Computer Vision Intern
Role ID: NVIDIA-02
Company: NVIDIA
Location: Bengaluru, India
Duration: 3 months (simulated)
Stipend: INR 70,000/month (simulated)
Deadline: 2026-12-27 (simulated)
Eligibility: B.Tech students in relevant computing disciplines (simulated).
Required skills: Python; OpenCV; image processing; CNNs; PyTorch; evaluation metrics
Preferred skills: Object detection; segmentation; CUDA; ONNX; deployment
Responsibilities: Build vision pipelines; curate datasets; test accuracy and latency
Relevant resume evidence: Detection, segmentation or image classification projects
Evaluation: Only cite resume-supported evidence; no protected-trait scoring.

## 3. Deep Learning Intern
Role ID: NVIDIA-03
Company: NVIDIA
Location: Bengaluru, India
Duration: 3 months (simulated)
Stipend: INR 75,000/month (simulated)
Deadline: 2026-12-30 (simulated)
Eligibility: B.Tech students in relevant computing disciplines (simulated).
Required skills: Python; neural networks; backpropagation; PyTorch; experiment tracking; statistics
Preferred skills: Transformers; distributed training; CUDA; optimization; MLOps
Responsibilities: Design experiments; tune neural models; analyze training behavior; reproduce baselines
Relevant resume evidence: Transformer, representation learning or deep learning research projects
Evaluation: Only cite resume-supported evidence; no protected-trait scoring.');
