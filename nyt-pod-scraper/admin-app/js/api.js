/**
 * Pod Monitor Admin - API Client Module
 * Handles all backend communication with demo mode fallback.
 */

// ============================================================
// DEMO DATA
// ============================================================

const DEMO_DATA = {
  podcasts: [
    {
      id: 'pod-1',
      name: 'The Health Policy Pod',
      feed_url: 'https://feeds.example.com/health-policy-pod/rss',
      category: 'health-policy',
      description: 'Weekly deep dives into UK and global health policy, featuring interviews with policymakers, NHS leaders, and health economists. Essential listening for understanding the forces shaping modern healthcare.',
      active: true,
      episode_count: 3,
      last_scraped: '2026-02-13T08:30:00Z',
      created_at: '2025-11-01T10:00:00Z'
    },
    {
      id: 'pod-2',
      name: 'Medical Frontiers Weekly',
      feed_url: 'https://feeds.example.com/medical-frontiers/rss',
      category: 'medical-research',
      description: 'Cutting-edge medical research explained for clinicians and health journalists. Each episode unpacks a landmark study or emerging therapy, from gene editing to novel immunotherapies.',
      active: true,
      episode_count: 3,
      last_scraped: '2026-02-13T07:45:00Z',
      created_at: '2025-10-15T09:00:00Z'
    },
    {
      id: 'pod-3',
      name: 'Public Health Today',
      feed_url: 'https://feeds.example.com/public-health-today/rss',
      category: 'public-health',
      description: 'Daily briefings on public health developments worldwide. From disease outbreaks to vaccination campaigns, health equity to environmental health, covering the stories that affect population health.',
      active: true,
      episode_count: 2,
      last_scraped: '2026-02-12T18:15:00Z',
      created_at: '2025-12-01T14:00:00Z'
    },
    {
      id: 'pod-4',
      name: 'Clinical Conversations',
      feed_url: 'https://feeds.example.com/clinical-conversations/rss',
      category: 'clinical',
      description: 'Practising clinicians discuss the cases, guidelines, and controversies that matter at the bedside. Bridging the gap between published evidence and real-world clinical decision-making.',
      active: false,
      episode_count: 2,
      last_scraped: '2026-02-10T12:00:00Z',
      created_at: '2025-09-20T11:00:00Z'
    }
  ],

  episodes: [
    // Health Policy Pod episodes
    {
      id: 'ep-1',
      podcast_id: 'pod-1',
      podcast_name: 'The Health Policy Pod',
      title: 'NHS Workforce Plan: Will It Deliver?',
      date: '2026-02-12T09:00:00Z',
      duration: '42:15',
      status: 'summarized',
      audio_url: 'https://example.com/audio/ep1.mp3',
      transcript: `Welcome to The Health Policy Pod. I'm Dr Sarah Mitchell, and today we're examining the NHS Long Term Workforce Plan one year on from its initial publication.

Joining me is Professor James Thornton from the Health Foundation and Dr Amara Osei, a former senior adviser to NHS England.

James, let's start with the headline numbers. The plan committed to doubling medical school places by 2031. Where are we on that trajectory?

Professor Thornton: Well Sarah, the short answer is we're behind schedule. We've seen a modest increase of about 15% in medical school intake, but the infrastructure simply isn't there yet. Several of the proposed new medical schools are still in planning stages. The challenge isn't just about creating places — it's about having enough clinical placements, supervisors, and teaching facilities to support those students.

Dr Osei: I'd add that even if we hit every target, we're still playing catch-up. The modelling assumed certain retention rates that frankly aren't materialising. We're losing experienced staff to burnout, early retirement, and emigration at rates that outpace our training pipeline. The plan needs to be viewed alongside serious work on retention, which has been somewhat neglected.

Sarah: Let's talk about the general practice element specifically. The plan promised significant increases in GP training places.

Professor Thornton: GP training fill rates have improved marginally, but the underlying problem is one of attractiveness. Young doctors are increasingly choosing hospital specialties or portfolio careers. Until we address the structural issues — the workload, the premises, the partnership model — simply offering more training places won't fill the gap. We need a fundamental rethink of what general practice looks like for the next generation.

Dr Osei: Absolutely. And there's a crucial international dimension here. The plan acknowledged reliance on international recruitment but didn't adequately plan for the ethical implications or the competitive global market for health workers. Countries across Europe and the Gulf states are actively recruiting from the same pools. We cannot assume the same supply lines will hold.

Sarah: One area where there has been progress is in apprenticeship routes and new roles. Can you speak to that?

Professor Thornton: Yes, the expansion of physician associate, nursing associate, and advanced practitioner roles has moved faster than traditional medical training expansion. But this creates its own tensions. There's ongoing debate about scope of practice, supervision requirements, and whether these roles are genuinely expanding capacity or simply shifting tasks without adequate safety frameworks.

Dr Osei: The political dimension matters too. We're heading into a period where health spending will face renewed pressure. The workforce plan requires sustained investment over fifteen years, but political cycles operate on much shorter timescales. Without cross-party commitment, there's a real risk that funding gets diverted when the next crisis hits.`,
      summary: 'This episode examines the NHS Long Term Workforce Plan twelve months after publication, with analysis from Professor James Thornton (Health Foundation) and Dr Amara Osei (former NHS England adviser). The discussion reveals that medical school expansion is running behind the target of doubling places by 2031, with only 15% growth achieved so far due to infrastructure and clinical placement constraints. Key concerns include deteriorating staff retention that outpaces the training pipeline, persistent difficulties filling GP training places due to structural disincentives, ethical questions around international recruitment in a competitive global market, and tensions surrounding the rapid expansion of physician associate and advanced practitioner roles. Both experts warn that the plan\'s fifteen-year timeline clashes with shorter political cycles and that sustained cross-party funding commitment remains uncertain.',
      gist: 'The NHS workforce plan is behind schedule on medical school expansion and faces headwinds from poor retention, GP recruitment challenges, and political uncertainty over sustained long-term funding.',
      themes: ['NHS workforce', 'Medical education', 'GP recruitment', 'Health policy funding', 'Staff retention'],
      key_quotes: [
        { text: 'We\'re losing experienced staff to burnout, early retirement, and emigration at rates that outpace our training pipeline.', speaker: 'Dr Amara Osei' },
        { text: 'Until we address the structural issues, simply offering more training places won\'t fill the gap.', speaker: 'Professor James Thornton' },
        { text: 'Without cross-party commitment, there\'s a real risk that funding gets diverted when the next crisis hits.', speaker: 'Dr Amara Osei' }
      ]
    },
    {
      id: 'ep-2',
      podcast_id: 'pod-1',
      podcast_name: 'The Health Policy Pod',
      title: 'Integrated Care Systems: Progress Report',
      date: '2026-02-05T09:00:00Z',
      duration: '38:50',
      status: 'summarized',
      audio_url: 'https://example.com/audio/ep2.mp3',
      transcript: `Today on The Health Policy Pod we're taking stock of Integrated Care Systems, now well into their second full year of operation.

I'm joined by Rachel Humphries, chief executive of an ICS in the Midlands, and Dr Kwame Asante, a GP and population health researcher at King's College London.

Rachel, from the ground level, how would you characterise the ICS experiment so far?

Rachel: I think we're at a genuinely pivotal moment. The first year was largely structural — establishing boards, agreeing governance, building relationships. Now we're into the harder work of actually changing how care is delivered across organisational boundaries. Some areas are seeing real progress in joint working between councils, NHS trusts, and primary care. But I won't pretend it's easy. Competing financial pressures, different organisational cultures, and the sheer complexity of aligning incentives across multiple bodies — it's a significant undertaking.

Dr Asante: From a population health perspective, the promise of ICSs was that they would shift focus from treating illness to preventing it, from hospital-centric care to community-based support. In some places that is happening — I've seen excellent examples of joint commissioning for mental health services and integrated approaches to childhood obesity. But in too many areas, the urgent still crowds out the important. When hospitals are in financial deficit and ambulances are queuing, the political space for long-term prevention work shrinks dramatically.

Rachel: That's exactly right. We're trying to build a new model of care while simultaneously managing unprecedented operational pressures. The analogy I use is rebuilding the aeroplane while it's flying through turbulence.

Dr Asante: And the data infrastructure isn't where it needs to be. Population health management requires sophisticated data sharing across primary care, secondary care, social care, and public health. Most ICSs are still wrestling with basic interoperability challenges. Without good data, you can't identify the communities with the greatest need or measure whether your interventions are working.`,
      summary: 'This episode reviews the progress of Integrated Care Systems in their second full year, with perspectives from ICS chief executive Rachel Humphries and population health researcher Dr Kwame Asante. While structural foundations are now in place and some areas show genuine progress in joint commissioning and cross-organisational working, significant challenges persist. Financial pressures on individual organisations, competing incentive structures, and deep cultural differences between NHS trusts and local authorities impede integration. The promise of shifting from hospital-centric treatment to population health prevention is only partially realised, as operational crises continue to dominate attention and resources. Data infrastructure remains a critical bottleneck, with most ICSs unable to share information effectively across primary care, secondary care, and social care systems.',
      gist: 'Integrated Care Systems are past the structural setup phase but struggling to deliver on population health ambitions due to financial pressures, operational crises, and inadequate data infrastructure.',
      themes: ['Integrated care', 'Population health', 'NHS reform', 'Data interoperability', 'Prevention'],
      key_quotes: [
        { text: 'We\'re trying to build a new model of care while simultaneously managing unprecedented operational pressures.', speaker: 'Rachel Humphries' },
        { text: 'In too many areas, the urgent still crowds out the important.', speaker: 'Dr Kwame Asante' }
      ]
    },
    {
      id: 'ep-3',
      podcast_id: 'pod-1',
      podcast_name: 'The Health Policy Pod',
      title: 'Mental Health Parity: Rhetoric vs Reality',
      date: '2026-01-29T09:00:00Z',
      duration: '45:30',
      status: 'transcribed',
      audio_url: 'https://example.com/audio/ep3.mp3',
      transcript: `On today's episode we confront a question that has dogged health policy for over a decade: are we any closer to genuine parity of esteem between mental and physical health?

My guests are Dr Fiona Mackenzie, a consultant psychiatrist and former president of the Royal College of Psychiatrists, and Tom Rivera, director of policy at Mind.

Fiona, governments of all stripes have pledged parity. Where does that commitment stand today?

Dr Mackenzie: The rhetoric has never been stronger, but the gap between words and reality remains troubling. Mental health services still receive roughly 11% of the NHS budget despite accounting for around 23% of the burden of disease. Waiting times for talking therapies are lengthening, not shortening. CAMHS services are still turning away children who desperately need help. We've seen some welcome investment — the expansion of crisis teams, the growth of IAPT — but it falls well short of what parity actually requires.

Tom: I'd echo that assessment from the charity perspective. When we survey people trying to access mental health support, the picture is deeply concerning. Average waits of six months or more for specialist treatment, people being told they're not ill enough for services but too ill for self-help, a postcode lottery that determines what care you receive. The concept of parity is meaningless if you're a young person in crisis being told there's an eighteen-month wait for an eating disorder service.

Dr Mackenzie: And the workforce crisis hits mental health particularly hard. We have a third fewer psychiatrists than we need, and recruitment into the specialty remains challenging. Many trainees are deterred by the intensity of the work, the conditions in inpatient settings, and frankly the lower status that psychiatric practice still holds in some medical circles.`,
      summary: null,
      gist: null,
      themes: [],
      key_quotes: []
    },

    // Medical Frontiers Weekly episodes
    {
      id: 'ep-4',
      podcast_id: 'pod-2',
      podcast_name: 'Medical Frontiers Weekly',
      title: 'CRISPR Gene Therapy for Sickle Cell: Two-Year Follow-Up',
      date: '2026-02-11T07:00:00Z',
      duration: '35:40',
      status: 'summarized',
      audio_url: 'https://example.com/audio/ep4.mp3',
      transcript: `Welcome to Medical Frontiers Weekly. I'm Professor Liam Chen, and this week we're looking at landmark two-year follow-up data for CRISPR-based gene therapy in sickle cell disease.

Dr Nkechi Adebayo, a haematologist at Guy's and St Thomas', has been involved in the UK arm of the Casgevy trials and joins us to discuss the results.

Nkechi, these two-year data have generated enormous excitement. Give us the headline findings.

Dr Adebayo: The results are genuinely remarkable. Of the 44 patients in the pivotal trial who received exa-cel — now branded Casgevy — 42 have remained free of vaso-occlusive crises for the entire two-year follow-up period. That's a 95.5% sustained response rate. Fetal haemoglobin levels have remained stably elevated, averaging around 40% of total haemoglobin, which is well above the threshold needed to prevent sickling. Patients report dramatic improvements in quality of life, pain scores, hospital admissions, and ability to work or attend school.

Professor Chen: What about safety signals at two years?

Dr Adebayo: The safety profile has been reassuring. The main toxicity remains the myeloablative conditioning required before infusion — essentially chemotherapy to make room in the bone marrow for the edited cells. That carries real risks: infections, infertility concerns, the theoretical long-term risk of secondary malignancies from the busulfan conditioning. We haven't seen any off-target editing effects or insertional oncogenesis in any patient, but two years is still relatively short for assessing those risks. The haematology community is cautiously optimistic but appropriately watchful.

Professor Chen: The access question looms large. At a list price exceeding two million dollars per treatment, how do you see this scaling?

Dr Adebayo: This is arguably the biggest challenge. Sickle cell disease affects millions of people globally, overwhelmingly in Sub-Saharan Africa and South Asia — regions with the least capacity to deliver this kind of complex, expensive therapy. Even in high-income settings, the manufacturing and delivery logistics are formidable. Each treatment is bespoke — you harvest the patient's own cells, edit them ex vivo, and reinfuse. There's no way to mass-produce this in the traditional pharmaceutical sense. We need creative approaches to manufacturing, pricing, and delivery if this breakthrough is to benefit more than a privileged few.`,
      summary: 'This episode examines two-year follow-up data from the CRISPR gene therapy (Casgevy/exa-cel) trial for sickle cell disease, discussed with haematologist Dr Nkechi Adebayo. Results show a 95.5% sustained response rate, with 42 of 44 patients remaining free of vaso-occlusive crises over the full follow-up period and maintaining therapeutic fetal haemoglobin levels around 40%. Patients report transformative quality-of-life improvements. The safety profile is reassuring with no off-target editing effects detected, though the myeloablative conditioning carries risks including infertility and theoretical secondary malignancy concerns. The episode highlights the critical access challenge: at over two million dollars per treatment, with bespoke per-patient manufacturing requirements, scaling to the millions of sickle cell patients worldwide — predominantly in Sub-Saharan Africa — presents formidable logistical, ethical, and economic obstacles.',
      gist: 'Two-year CRISPR gene therapy data for sickle cell disease show 95.5% sustained response, but scaling a bespoke two-million-dollar treatment to millions of patients globally remains the defining challenge.',
      themes: ['Gene therapy', 'CRISPR', 'Sickle cell disease', 'Health equity', 'Drug pricing'],
      key_quotes: [
        { text: 'Of the 44 patients who received exa-cel, 42 have remained free of vaso-occlusive crises for the entire two-year follow-up period.', speaker: 'Dr Nkechi Adebayo' },
        { text: 'We need creative approaches to manufacturing, pricing, and delivery if this breakthrough is to benefit more than a privileged few.', speaker: 'Dr Nkechi Adebayo' }
      ]
    },
    {
      id: 'ep-5',
      podcast_id: 'pod-2',
      podcast_name: 'Medical Frontiers Weekly',
      title: 'GLP-1 Agonists Beyond Diabetes: Cardiovascular Outcomes',
      date: '2026-02-04T07:00:00Z',
      duration: '40:20',
      status: 'summarized',
      audio_url: 'https://example.com/audio/ep5.mp3',
      transcript: `This week on Medical Frontiers we explore the expanding evidence for GLP-1 receptor agonists beyond their original indications, with a particular focus on the cardiovascular outcomes data.

Professor Helen Whitworth is a cardiologist and clinical trialist at the University of Oxford who has been closely tracking this space.

Helen, the SELECT trial data landed with enormous impact. What did it show?

Professor Whitworth: SELECT was a landmark. Over 17,000 patients with established cardiovascular disease and obesity but without diabetes were randomised to semaglutide or placebo. The primary endpoint — a composite of cardiovascular death, non-fatal MI, or non-fatal stroke — was reduced by 20% in the semaglutide group. That's a highly significant result that fundamentally changes how we think about the relationship between obesity treatment and cardiovascular risk reduction.

What makes this particularly striking is that the cardiovascular benefit appeared to be at least partially independent of the magnitude of weight loss. Patients who lost relatively modest amounts of weight still showed meaningful cardiovascular risk reduction, suggesting direct anti-inflammatory or anti-atherosclerotic effects of the drug beyond its metabolic impact.

Professor Chen: The mechanistic data are fascinating, aren't they?

Professor Whitworth: Enormously so. We're seeing evidence of reduced vascular inflammation, improved endothelial function, and favourable effects on arterial plaque composition — plaques becoming more stable and less prone to rupture. There are emerging data on beneficial effects on kidney function, liver steatosis, and potentially even neurodegenerative conditions. It's becoming clear that GLP-1 receptor agonism has far more systemic effects than we initially appreciated.

The challenge for clinicians is navigating this rapidly evolving landscape. We're moving from seeing these drugs as diabetes medications that happen to help with weight, to potentially seeing them as cardiovascular risk reduction agents that happen to help with diabetes and weight. That's a Copernican shift in how we position them therapeutically.`,
      summary: 'This episode analyses the expanding evidence base for GLP-1 receptor agonists in cardiovascular disease, discussed with cardiologist Professor Helen Whitworth. The SELECT trial demonstrated a 20% reduction in major adverse cardiovascular events (death, MI, stroke) with semaglutide in patients with obesity and cardiovascular disease but without diabetes. Critically, the cardiovascular benefit appears at least partially independent of weight loss magnitude, pointing to direct anti-inflammatory and anti-atherosclerotic drug effects including reduced vascular inflammation, improved endothelial function, and favourable plaque remodelling. The episode discusses the emerging paradigm shift from viewing GLP-1 agonists as diabetes drugs that aid weight loss, to regarding them as cardiovascular risk reduction agents with broad systemic benefits spanning kidney function, liver disease, and potentially neurodegeneration. Barriers to widespread adoption include cost, supply constraints, gastrointestinal tolerability, and defining which patient populations derive the greatest benefit.',
      gist: 'The SELECT trial shows semaglutide cuts cardiovascular events by 20% in obese patients without diabetes, signalling a paradigm shift toward viewing GLP-1 agonists as cardiovascular risk reduction agents.',
      themes: ['GLP-1 agonists', 'Cardiovascular outcomes', 'Obesity treatment', 'Clinical trials', 'Semaglutide'],
      key_quotes: [
        { text: 'The cardiovascular benefit appeared to be at least partially independent of the magnitude of weight loss.', speaker: 'Professor Helen Whitworth' },
        { text: 'We\'re moving from seeing these drugs as diabetes medications that happen to help with weight, to cardiovascular risk reduction agents that happen to help with diabetes and weight.', speaker: 'Professor Helen Whitworth' }
      ]
    },
    {
      id: 'ep-6',
      podcast_id: 'pod-2',
      podcast_name: 'Medical Frontiers Weekly',
      title: 'AI-Assisted Pathology: Promise and Pitfalls',
      date: '2026-01-28T07:00:00Z',
      duration: '37:10',
      status: 'new',
      audio_url: 'https://example.com/audio/ep6.mp3',
      transcript: null,
      summary: null,
      gist: null,
      themes: [],
      key_quotes: []
    },

    // Public Health Today episodes
    {
      id: 'ep-7',
      podcast_id: 'pod-3',
      podcast_name: 'Public Health Today',
      title: 'Measles Resurgence in Europe: Lessons Not Learned',
      date: '2026-02-10T06:00:00Z',
      duration: '28:45',
      status: 'summarized',
      audio_url: 'https://example.com/audio/ep7.mp3',
      transcript: `Good morning and welcome to Public Health Today. I'm Dr Maria Santos, and our lead story examines the continuing measles resurgence across Europe.

Dr Henrik Larsson from the European Centre for Disease Prevention and Control joins us with the latest surveillance data.

Henrik, the numbers paint a worrying picture.

Dr Larsson: They do, Maria. We've recorded over 58,000 confirmed measles cases across the WHO European Region in the past twelve months — more than triple the figure from the previous year. Several countries that had previously achieved elimination status have seen sustained transmission re-establish. Romania, the UK, Austria, and parts of Germany and France have been particularly affected.

What's especially concerning is the age distribution. We're seeing significant numbers of cases in children under five who have missed routine vaccinations, but also a growing cohort of adolescents and young adults who fell through the gaps during previous years of suboptimal coverage. These aren't just mild childhood infections — we've seen over 200 cases of encephalitis and, tragically, 14 deaths across the region.

Dr Santos: What's driving the decline in vaccine coverage?

Dr Larsson: It's multifactorial. The pandemic disrupted routine immunisation programmes everywhere, and many countries have not fully recovered their pre-pandemic coverage levels. But the pandemic also turbocharged misinformation and erosion of trust in public health institutions. We're seeing active anti-vaccination campaigns that have become more sophisticated, more targeted, and more effective at reaching vaccine-hesitant parents through social media.

There are also structural factors — in some countries, accessing vaccination requires multiple visits to health facilities during working hours, which disproportionately affects lower-income families. In others, healthcare system fragmentation means there's no comprehensive recall system for children who miss their scheduled doses.`,
      summary: 'This episode covers the alarming measles resurgence across Europe, with ECDC epidemiologist Dr Henrik Larsson reporting over 58,000 confirmed cases in the past year — a threefold increase — including 200+ encephalitis cases and 14 deaths. Several countries that had achieved elimination status, including the UK and Romania, now have sustained transmission. The resurgence affects both under-five children who missed routine vaccinations and adolescents who fell through coverage gaps in earlier years. Contributing factors include pandemic disruption of immunisation programmes, sophisticated anti-vaccination social media campaigns that eroded public trust, and structural access barriers that disproportionately affect lower-income families. The episode argues that measles resurgence is a sentinel indicator of broader immunisation programme fragility and calls for urgent investment in vaccine delivery infrastructure, targeted community engagement, and regulatory action against organised misinformation.',
      gist: 'Europe has recorded 58,000 measles cases in the past year with 14 deaths, driven by pandemic-era immunisation disruption, social media anti-vaccine campaigns, and structural access barriers.',
      themes: ['Measles', 'Vaccination', 'Misinformation', 'Public health infrastructure', 'Health equity'],
      key_quotes: [
        { text: 'The pandemic turbocharged misinformation and erosion of trust in public health institutions.', speaker: 'Dr Henrik Larsson' },
        { text: 'Anti-vaccination campaigns have become more sophisticated, more targeted, and more effective at reaching vaccine-hesitant parents through social media.', speaker: 'Dr Henrik Larsson' }
      ]
    },
    {
      id: 'ep-8',
      podcast_id: 'pod-3',
      podcast_name: 'Public Health Today',
      title: 'Ultra-Processed Foods: The Emerging Evidence Base',
      date: '2026-02-03T06:00:00Z',
      duration: '32:20',
      status: 'transcribed',
      audio_url: 'https://example.com/audio/ep8.mp3',
      transcript: `Today we examine the rapidly growing evidence linking ultra-processed food consumption to adverse health outcomes, and what it means for public health policy.

Professor Claire Donovan, a nutritional epidemiologist at Imperial College London, has been at the forefront of this research.

Claire, the term ultra-processed food has entered mainstream consciousness, but there remains debate about the evidence. Where do things stand scientifically?

Professor Donovan: The evidence base has grown enormously in the past two years. We now have multiple large prospective cohort studies from across the world consistently showing associations between higher ultra-processed food consumption and increased risk of obesity, type 2 diabetes, cardiovascular disease, certain cancers — particularly colorectal — depression, and all-cause mortality. The NOVA classification system, which categorises foods by degree of processing, has become the standard framework.

But I want to be honest about the limitations. Most of this evidence is observational. It's very difficult to fully control for confounding — people who eat more ultra-processed food tend to differ from those who don't in many ways: income, education, physical activity, overall dietary patterns. The few randomised trials we have — most notably Kevin Hall's NIH study — showed that people spontaneously consume about 500 more calories per day when offered ultra-processed diets versus unprocessed alternatives, leading to measurable weight gain in just two weeks. But we need more interventional data.

Professor Donovan: The mechanistic pathways are also becoming clearer. Ultra-processing often introduces emulsifiers, artificial sweeteners, and other additives that appear to disrupt the gut microbiome. There's evidence that the physical structure of ultra-processed foods — being softer and requiring less chewing — leads to faster eating and delayed satiety signalling. And the combination of specific ratios of sugar, fat, and salt appears to engage reward pathways in ways that promote overconsumption.`,
      summary: null,
      gist: null,
      themes: [],
      key_quotes: []
    },

    // Clinical Conversations episodes
    {
      id: 'ep-9',
      podcast_id: 'pod-4',
      podcast_name: 'Clinical Conversations',
      title: 'Antibiotic Stewardship in Primary Care: Practical Strategies',
      date: '2026-02-07T12:00:00Z',
      duration: '34:55',
      status: 'summarized',
      audio_url: 'https://example.com/audio/ep9.mp3',
      transcript: `Welcome to Clinical Conversations. I'm Dr Priya Sharma, and today we're tackling one of the most persistent challenges in primary care: antibiotic prescribing.

Dr Marcus Webb is a GP in Bristol who has led an award-winning antibiotic stewardship programme across his primary care network.

Marcus, antimicrobial resistance is described as a slow pandemic. How does that framing land in general practice?

Dr Webb: I think the problem for GPs is that AMR feels abstract and distant when you're sitting opposite a patient with a sore throat who's struggling to swallow and asking for antibiotics. The individual risk-benefit calculation in that consultation — where the antibiotic probably won't help much but the patient will feel they've been heard — often overwhelms the collective risk-benefit calculation about resistance. Our job in stewardship is to make the right thing the easy thing.

What we did in our network was implement a three-pronged approach. First, we redesigned our consultation templates to include delayed prescribing as a default option — patients receive a prescription that they're asked not to fill for 48 hours, with clear safety-netting advice. Second, we invested in point-of-care CRP testing, which gives clinicians an objective measure to support their decision not to prescribe. Third — and this was crucial — we ran workshops on communication skills. The evidence shows that a two-minute conversation explaining why antibiotics won't help, delivered with empathy, is as effective as prescribing in terms of patient satisfaction.

Dr Sharma: And what were the results?

Dr Webb: Over eighteen months we achieved a 23% reduction in total antibiotic prescribing across the network, with particular reductions in broad-spectrum agents. Patient satisfaction scores actually improved slightly. Reconsultation rates — patients coming back because they weren't getting better — didn't increase. And critically, our GPs reported lower levels of consultation-related stress because they had the tools and confidence to have those conversations.`,
      summary: 'This episode explores practical antibiotic stewardship strategies in primary care with Dr Marcus Webb, a GP who led a successful programme across his Bristol primary care network. His three-pronged approach combined default delayed prescribing templates, point-of-care CRP testing to support clinical decision-making, and communication skills workshops focused on empathetic explanation. The programme achieved a 23% reduction in total antibiotic prescribing over eighteen months without increasing reconsultation rates, while patient satisfaction scores slightly improved and GP stress around prescribing consultations decreased. The episode discusses the broader context of antimicrobial resistance as a collective action problem, the tension between individual consultation decisions and population-level consequences, the role of diagnostic uncertainty in driving unnecessary prescribing, and the importance of system-level changes that make appropriate prescribing the default rather than relying solely on individual clinician behaviour change.',
      gist: 'A Bristol GP network achieved 23% antibiotic prescribing reduction through delayed prescribing defaults, point-of-care CRP testing, and communication skills training, without compromising patient satisfaction.',
      themes: ['Antimicrobial resistance', 'Antibiotic stewardship', 'Primary care', 'Behaviour change', 'Point-of-care testing'],
      key_quotes: [
        { text: 'Our job in stewardship is to make the right thing the easy thing.', speaker: 'Dr Marcus Webb' },
        { text: 'A two-minute conversation explaining why antibiotics won\'t help, delivered with empathy, is as effective as prescribing in terms of patient satisfaction.', speaker: 'Dr Marcus Webb' }
      ]
    },
    {
      id: 'ep-10',
      podcast_id: 'pod-4',
      podcast_name: 'Clinical Conversations',
      title: 'Managing Diagnostic Uncertainty in Emergency Medicine',
      date: '2026-01-31T12:00:00Z',
      duration: '41:00',
      status: 'new',
      audio_url: 'https://example.com/audio/ep10.mp3',
      transcript: null,
      summary: null,
      gist: null,
      themes: [],
      key_quotes: []
    }
  ],

  distribution_lists: {
    daily: [
      'editor@bmj.com',
      'news.desk@bmj.com',
      'features@bmj.com',
      'digital@bmj.com',
      'sarah.mitchell@bmj.com'
    ],
    weekly: [
      'editor@bmj.com',
      'news.desk@bmj.com',
      'features@bmj.com',
      'commissioning@bmj.com',
      'research@bmj.com',
      'education@bmj.com',
      'policy@bmj.com',
      'digital@bmj.com'
    ]
  },

  config: {
    llm_provider: 'anthropic',
    api_key: '',
    model: 'claude-sonnet-4-20250514',
    scrape_interval_hours: 6,
    max_episodes_per_feed: 10,
    smtp_host: 'smtp.bmj.com',
    smtp_port: 587,
    smtp_user: 'podmonitor@bmj.com',
    smtp_password: '',
    from_email: 'Pod Monitor <podmonitor@bmj.com>',
    from_name: 'BMJ Pod Monitor'
  }
};

// ============================================================
// EMAIL TEMPLATES
// ============================================================

function generateDailyEmailHTML() {
  const today = new Date().toLocaleDateString('en-GB', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
  return `
<div style="max-width:640px;margin:0 auto;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;color:#212529;">
  <div style="background:#005EB8;padding:24px 32px;border-radius:8px 8px 0 0;">
    <h1 style="color:#fff;margin:0;font-size:22px;font-weight:700;">BMJ Pod Monitor</h1>
    <p style="color:rgba(255,255,255,0.85);margin:6px 0 0;font-size:14px;">Daily Podcast Intelligence Digest</p>
    <p style="color:rgba(255,255,255,0.7);margin:4px 0 0;font-size:13px;">${today}</p>
  </div>

  <div style="background:#fff;border:1px solid #e9ecef;border-top:none;padding:32px;">
    <p style="font-size:15px;line-height:1.6;color:#495057;margin:0 0 24px;">
      Good morning. Here is your daily summary of new podcast episodes monitored overnight, with AI-generated analysis of key themes and quotes relevant to BMJ editorial coverage.
    </p>

    <div style="margin-bottom:32px;">
      <div style="border-left:4px solid #005EB8;padding-left:16px;margin-bottom:8px;">
        <h2 style="font-size:17px;margin:0;color:#212529;">The Health Policy Pod</h2>
        <p style="font-size:13px;color:#6c757d;margin:4px 0 0;">NHS Workforce Plan: Will It Deliver?</p>
      </div>
      <div style="background:#f8f9fa;padding:16px;border-radius:4px;margin-top:12px;">
        <p style="font-size:14px;line-height:1.7;color:#212529;margin:0 0 12px;">
          <strong>Summary:</strong> The NHS workforce plan is behind schedule on medical school expansion (15% growth vs. doubling target) and faces headwinds from poor retention, GP recruitment challenges, and political uncertainty over sustained funding. Experts warn the fifteen-year plan clashes with shorter political cycles.
        </p>
        <p style="font-size:13px;color:#6c757d;margin:0;">
          <strong>Themes:</strong>
          <span style="display:inline-block;padding:2px 8px;background:rgba(0,94,184,0.08);color:#005EB8;border-radius:12px;font-size:12px;margin:2px 4px 2px 0;">NHS workforce</span>
          <span style="display:inline-block;padding:2px 8px;background:rgba(0,94,184,0.08);color:#005EB8;border-radius:12px;font-size:12px;margin:2px 4px 2px 0;">Medical education</span>
          <span style="display:inline-block;padding:2px 8px;background:rgba(0,94,184,0.08);color:#005EB8;border-radius:12px;font-size:12px;margin:2px 4px 2px 0;">Staff retention</span>
        </p>
      </div>
      <blockquote style="border-left:3px solid #6F42C1;margin:12px 0 0;padding:8px 16px;background:rgba(111,66,193,0.04);border-radius:0 4px 4px 0;">
        <p style="font-size:13px;font-style:italic;color:#212529;margin:0 0 4px;">"We're losing experienced staff to burnout, early retirement, and emigration at rates that outpace our training pipeline."</p>
        <cite style="font-size:12px;color:#6c757d;font-style:normal;">-- Dr Amara Osei</cite>
      </blockquote>
    </div>

    <div style="margin-bottom:32px;">
      <div style="border-left:4px solid #6F42C1;padding-left:16px;margin-bottom:8px;">
        <h2 style="font-size:17px;margin:0;color:#212529;">Medical Frontiers Weekly</h2>
        <p style="font-size:13px;color:#6c757d;margin:4px 0 0;">CRISPR Gene Therapy for Sickle Cell: Two-Year Follow-Up</p>
      </div>
      <div style="background:#f8f9fa;padding:16px;border-radius:4px;margin-top:12px;">
        <p style="font-size:14px;line-height:1.7;color:#212529;margin:0 0 12px;">
          <strong>Summary:</strong> Two-year follow-up data show 95.5% sustained response rate for CRISPR-based sickle cell therapy (Casgevy). Of 44 patients, 42 remained free of vaso-occlusive crises. No off-target editing detected, but scaling a bespoke two-million-dollar treatment to millions of patients globally remains the defining challenge.
        </p>
        <p style="font-size:13px;color:#6c757d;margin:0;">
          <strong>Themes:</strong>
          <span style="display:inline-block;padding:2px 8px;background:rgba(0,94,184,0.08);color:#005EB8;border-radius:12px;font-size:12px;margin:2px 4px 2px 0;">Gene therapy</span>
          <span style="display:inline-block;padding:2px 8px;background:rgba(0,94,184,0.08);color:#005EB8;border-radius:12px;font-size:12px;margin:2px 4px 2px 0;">CRISPR</span>
          <span style="display:inline-block;padding:2px 8px;background:rgba(0,94,184,0.08);color:#005EB8;border-radius:12px;font-size:12px;margin:2px 4px 2px 0;">Health equity</span>
        </p>
      </div>
      <blockquote style="border-left:3px solid #6F42C1;margin:12px 0 0;padding:8px 16px;background:rgba(111,66,193,0.04);border-radius:0 4px 4px 0;">
        <p style="font-size:13px;font-style:italic;color:#212529;margin:0 0 4px;">"We need creative approaches to manufacturing, pricing, and delivery if this breakthrough is to benefit more than a privileged few."</p>
        <cite style="font-size:12px;color:#6c757d;font-style:normal;">-- Dr Nkechi Adebayo</cite>
      </blockquote>
    </div>

    <div style="border-top:2px solid #005EB8;padding-top:20px;margin-top:32px;">
      <h3 style="font-size:15px;color:#005EB8;margin:0 0 12px;">Cross-Cutting Themes Today</h3>
      <ul style="margin:0;padding:0 0 0 20px;font-size:14px;line-height:1.8;color:#495057;">
        <li><strong>Workforce and capacity:</strong> Both the NHS workforce plan analysis and sickle cell therapy discussion highlight tensions between ambitious plans and the human/infrastructure capacity to deliver them.</li>
        <li><strong>Equity of access:</strong> The CRISPR therapy access challenge and workforce distribution concerns both raise questions about who benefits from medical advances.</li>
        <li><strong>Long-term commitment vs. short-term pressures:</strong> Recurring tension between what evidence demands and what political and economic realities allow.</li>
      </ul>
    </div>
  </div>

  <div style="background:#f8f9fa;padding:20px 32px;border:1px solid #e9ecef;border-top:none;border-radius:0 0 8px 8px;">
    <p style="font-size:12px;color:#6c757d;margin:0;text-align:center;">
      BMJ Pod Monitor -- AI-generated summaries for editorial reference only.<br>
      Verify all claims before publication. Content generated on ${today}.
    </p>
  </div>
</div>`;
}

function generateWeeklyEmailHTML() {
  const today = new Date();
  const weekStart = new Date(today);
  weekStart.setDate(today.getDate() - 7);
  const dateRange = `${weekStart.toLocaleDateString('en-GB', { day: 'numeric', month: 'long' })} -- ${today.toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' })}`;

  return `
<div style="max-width:640px;margin:0 auto;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;color:#212529;">
  <div style="background:linear-gradient(135deg,#005EB8 0%,#004A92 100%);padding:28px 32px;border-radius:8px 8px 0 0;">
    <h1 style="color:#fff;margin:0;font-size:24px;font-weight:700;">BMJ Pod Monitor</h1>
    <p style="color:rgba(255,255,255,0.85);margin:8px 0 0;font-size:15px;">Weekly Podcast Intelligence Report</p>
    <p style="color:rgba(255,255,255,0.7);margin:4px 0 0;font-size:13px;">${dateRange}</p>
  </div>

  <div style="background:#fff;border:1px solid #e9ecef;border-top:none;padding:32px;">

    <div style="background:#f8f9fa;border-radius:8px;padding:20px;margin-bottom:28px;">
      <h3 style="font-size:15px;margin:0 0 12px;color:#005EB8;">Week at a Glance</h3>
      <div style="display:flex;gap:16px;flex-wrap:wrap;">
        <div style="flex:1;min-width:120px;text-align:center;padding:12px;background:#fff;border-radius:4px;border:1px solid #e9ecef;">
          <div style="font-size:24px;font-weight:700;color:#005EB8;">6</div>
          <div style="font-size:12px;color:#6c757d;">New Episodes</div>
        </div>
        <div style="flex:1;min-width:120px;text-align:center;padding:12px;background:#fff;border-radius:4px;border:1px solid #e9ecef;">
          <div style="font-size:24px;font-weight:700;color:#28A745;">4</div>
          <div style="font-size:12px;color:#6c757d;">Summarised</div>
        </div>
        <div style="flex:1;min-width:120px;text-align:center;padding:12px;background:#fff;border-radius:4px;border:1px solid #e9ecef;">
          <div style="font-size:24px;font-weight:700;color:#6F42C1;">12</div>
          <div style="font-size:12px;color:#6c757d;">Key Themes</div>
        </div>
        <div style="flex:1;min-width:120px;text-align:center;padding:12px;background:#fff;border-radius:4px;border:1px solid #e9ecef;">
          <div style="font-size:24px;font-weight:700;color:#17A2B8;">4</div>
          <div style="font-size:12px;color:#6c757d;">Podcasts Tracked</div>
        </div>
      </div>
    </div>

    <h3 style="font-size:16px;color:#212529;margin:0 0 16px;padding-bottom:8px;border-bottom:2px solid #005EB8;">Episode Summaries</h3>

    <div style="margin-bottom:24px;padding-bottom:24px;border-bottom:1px solid #e9ecef;">
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:8px;">
        <span style="display:inline-block;padding:2px 8px;background:rgba(0,94,184,0.1);color:#005EB8;border-radius:4px;font-size:11px;font-weight:600;text-transform:uppercase;">Health Policy</span>
        <span style="font-size:12px;color:#6c757d;">12 Feb 2026</span>
      </div>
      <h4 style="font-size:15px;margin:0 0 8px;color:#212529;">NHS Workforce Plan: Will It Deliver?</h4>
      <p style="font-size:14px;line-height:1.7;color:#495057;margin:0;">The NHS workforce plan is behind schedule on medical school expansion and faces headwinds from poor staff retention, GP recruitment challenges, and political uncertainty over sustained long-term funding.</p>
    </div>

    <div style="margin-bottom:24px;padding-bottom:24px;border-bottom:1px solid #e9ecef;">
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:8px;">
        <span style="display:inline-block;padding:2px 8px;background:rgba(0,94,184,0.1);color:#005EB8;border-radius:4px;font-size:11px;font-weight:600;text-transform:uppercase;">Health Policy</span>
        <span style="font-size:12px;color:#6c757d;">5 Feb 2026</span>
      </div>
      <h4 style="font-size:15px;margin:0 0 8px;color:#212529;">Integrated Care Systems: Progress Report</h4>
      <p style="font-size:14px;line-height:1.7;color:#495057;margin:0;">ICSs are past the structural setup phase but struggling to deliver on population health ambitions due to financial pressures, operational crises, and inadequate data infrastructure.</p>
    </div>

    <div style="margin-bottom:24px;padding-bottom:24px;border-bottom:1px solid #e9ecef;">
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:8px;">
        <span style="display:inline-block;padding:2px 8px;background:rgba(111,66,193,0.1);color:#6F42C1;border-radius:4px;font-size:11px;font-weight:600;text-transform:uppercase;">Research</span>
        <span style="font-size:12px;color:#6c757d;">11 Feb 2026</span>
      </div>
      <h4 style="font-size:15px;margin:0 0 8px;color:#212529;">CRISPR Gene Therapy for Sickle Cell: Two-Year Follow-Up</h4>
      <p style="font-size:14px;line-height:1.7;color:#495057;margin:0;">Landmark two-year data show 95.5% sustained response rate for Casgevy in sickle cell disease. Scaling this bespoke two-million-dollar treatment to millions of patients globally remains the defining challenge.</p>
    </div>

    <div style="margin-bottom:24px;padding-bottom:24px;border-bottom:1px solid #e9ecef;">
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:8px;">
        <span style="display:inline-block;padding:2px 8px;background:rgba(111,66,193,0.1);color:#6F42C1;border-radius:4px;font-size:11px;font-weight:600;text-transform:uppercase;">Research</span>
        <span style="font-size:12px;color:#6c757d;">4 Feb 2026</span>
      </div>
      <h4 style="font-size:15px;margin:0 0 8px;color:#212529;">GLP-1 Agonists Beyond Diabetes: Cardiovascular Outcomes</h4>
      <p style="font-size:14px;line-height:1.7;color:#495057;margin:0;">SELECT trial shows semaglutide cuts cardiovascular events by 20% in obese non-diabetic patients, signalling a paradigm shift toward viewing GLP-1 agonists as cardiovascular risk reduction agents.</p>
    </div>

    <div style="margin-bottom:24px;padding-bottom:24px;border-bottom:1px solid #e9ecef;">
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:8px;">
        <span style="display:inline-block;padding:2px 8px;background:rgba(40,167,69,0.1);color:#1e7e34;border-radius:4px;font-size:11px;font-weight:600;text-transform:uppercase;">Public Health</span>
        <span style="font-size:12px;color:#6c757d;">10 Feb 2026</span>
      </div>
      <h4 style="font-size:15px;margin:0 0 8px;color:#212529;">Measles Resurgence in Europe: Lessons Not Learned</h4>
      <p style="font-size:14px;line-height:1.7;color:#495057;margin:0;">Europe recorded 58,000 measles cases in the past year with 14 deaths, driven by pandemic-era immunisation disruption, social media anti-vaccine campaigns, and structural access barriers.</p>
    </div>

    <div style="margin-bottom:24px;padding-bottom:24px;border-bottom:1px solid #e9ecef;">
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:8px;">
        <span style="display:inline-block;padding:2px 8px;background:rgba(23,162,184,0.1);color:#117a8b;border-radius:4px;font-size:11px;font-weight:600;text-transform:uppercase;">Clinical</span>
        <span style="font-size:12px;color:#6c757d;">7 Feb 2026</span>
      </div>
      <h4 style="font-size:15px;margin:0 0 8px;color:#212529;">Antibiotic Stewardship in Primary Care: Practical Strategies</h4>
      <p style="font-size:14px;line-height:1.7;color:#495057;margin:0;">A Bristol GP network achieved 23% antibiotic prescribing reduction through delayed prescribing defaults, point-of-care CRP testing, and communication skills training without compromising patient satisfaction.</p>
    </div>

    <div style="border-top:2px solid #005EB8;padding-top:20px;margin-top:8px;">
      <h3 style="font-size:15px;color:#005EB8;margin:0 0 12px;">Cross-Cutting Themes This Week</h3>
      <ul style="margin:0;padding:0 0 0 20px;font-size:14px;line-height:1.8;color:#495057;">
        <li><strong>Access and equity:</strong> From CRISPR therapy pricing to measles vaccine access barriers, the gap between breakthrough and benefit remains a dominant theme.</li>
        <li><strong>Workforce sustainability:</strong> NHS workforce planning, GP recruitment, and antibiotic stewardship all touch on whether the healthcare system has the people it needs.</li>
        <li><strong>Evidence-to-practice translation:</strong> Whether GLP-1 cardiovascular data, stewardship interventions, or ICS implementation, the challenge of turning evidence into changed practice recurs across all domains.</li>
        <li><strong>Trust and misinformation:</strong> Measles resurgence linked to vaccine misinformation underscores the fragility of public health infrastructure when trust erodes.</li>
        <li><strong>System complexity:</strong> ICS integration challenges and the interplay of political, financial, and clinical factors highlight healthcare as a complex adaptive system.</li>
      </ul>
    </div>

    <div style="background:rgba(111,66,193,0.04);border-left:4px solid #6F42C1;padding:16px;margin-top:28px;border-radius:0 8px 8px 0;">
      <h3 style="font-size:15px;color:#6F42C1;margin:0 0 12px;">Notable Quotes</h3>
      <div style="margin-bottom:12px;">
        <p style="font-size:13px;font-style:italic;color:#212529;margin:0 0 4px;">"We're losing experienced staff to burnout, early retirement, and emigration at rates that outpace our training pipeline."</p>
        <cite style="font-size:12px;color:#6c757d;font-style:normal;">-- Dr Amara Osei, on NHS workforce retention</cite>
      </div>
      <div style="margin-bottom:12px;">
        <p style="font-size:13px;font-style:italic;color:#212529;margin:0 0 4px;">"We need creative approaches to manufacturing, pricing, and delivery if this breakthrough is to benefit more than a privileged few."</p>
        <cite style="font-size:12px;color:#6c757d;font-style:normal;">-- Dr Nkechi Adebayo, on CRISPR gene therapy access</cite>
      </div>
      <div style="margin-bottom:12px;">
        <p style="font-size:13px;font-style:italic;color:#212529;margin:0 0 4px;">"The cardiovascular benefit appeared to be at least partially independent of the magnitude of weight loss."</p>
        <cite style="font-size:12px;color:#6c757d;font-style:normal;">-- Professor Helen Whitworth, on GLP-1 agonist mechanisms</cite>
      </div>
      <div>
        <p style="font-size:13px;font-style:italic;color:#212529;margin:0 0 4px;">"Our job in stewardship is to make the right thing the easy thing."</p>
        <cite style="font-size:12px;color:#6c757d;font-style:normal;">-- Dr Marcus Webb, on antibiotic prescribing</cite>
      </div>
    </div>
  </div>

  <div style="background:#f8f9fa;padding:20px 32px;border:1px solid #e9ecef;border-top:none;border-radius:0 0 8px 8px;">
    <p style="font-size:12px;color:#6c757d;margin:0;text-align:center;">
      BMJ Pod Monitor -- Weekly Intelligence Report<br>
      AI-generated summaries for editorial reference only. Verify all claims before publication.<br>
      ${dateRange}
    </p>
  </div>
</div>`;
}

// ============================================================
// API CLIENT
// ============================================================

let _apiBase = '/api';
let _demoMode = true;
let _demoData = JSON.parse(JSON.stringify(DEMO_DATA));

/**
 * Configure the API client.
 * @param {object} opts - { apiBase, demoMode }
 */
export function configure(opts = {}) {
  if (opts.apiBase !== undefined) _apiBase = opts.apiBase;
  if (opts.demoMode !== undefined) _demoMode = opts.demoMode;
}

/** Returns true if running in demo mode. */
export function isDemoMode() {
  return _demoMode;
}

/**
 * Attempt to reach the backend. Switches to demo mode on failure.
 */
export async function detectBackend() {
  try {
    const res = await fetch(`${_apiBase}/health`, { signal: AbortSignal.timeout(2000) });
    if (res.ok) {
      _demoMode = false;
      return true;
    }
  } catch {
    // Backend not available
  }
  _demoMode = true;
  return false;
}

// -- Helpers --

function delay(ms = 400) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function demoResponse(data) {
  await delay(Math.random() * 300 + 200);
  return JSON.parse(JSON.stringify(data));
}

async function apiFetch(path, opts = {}) {
  if (_demoMode) {
    throw new Error('Demo mode - should not reach apiFetch');
  }
  const res = await fetch(`${_apiBase}${path}`, {
    headers: { 'Content-Type': 'application/json', ...opts.headers },
    ...opts
  });
  if (!res.ok) {
    const errBody = await res.text();
    throw new Error(`API Error ${res.status}: ${errBody}`);
  }
  return res.json();
}

// ============================================================
// PODCASTS
// ============================================================

export async function fetchPodcasts() {
  if (_demoMode) return demoResponse(_demoData.podcasts);
  return apiFetch('/podcasts');
}

export async function addPodcast(data) {
  if (_demoMode) {
    const newPod = {
      id: 'pod-' + Date.now(),
      name: data.name,
      feed_url: data.feed_url,
      category: data.category || 'default',
      description: data.description || '',
      active: true,
      episode_count: 0,
      last_scraped: null,
      created_at: new Date().toISOString()
    };
    _demoData.podcasts.push(newPod);
    return demoResponse(newPod);
  }
  return apiFetch('/podcasts', { method: 'POST', body: JSON.stringify(data) });
}

export async function updatePodcast(id, data) {
  if (_demoMode) {
    const idx = _demoData.podcasts.findIndex(p => p.id === id);
    if (idx === -1) throw new Error('Podcast not found');
    Object.assign(_demoData.podcasts[idx], data);
    return demoResponse(_demoData.podcasts[idx]);
  }
  return apiFetch(`/podcasts/${id}`, { method: 'PUT', body: JSON.stringify(data) });
}

export async function deletePodcast(id) {
  if (_demoMode) {
    const idx = _demoData.podcasts.findIndex(p => p.id === id);
    if (idx === -1) throw new Error('Podcast not found');
    _demoData.podcasts.splice(idx, 1);
    _demoData.episodes = _demoData.episodes.filter(e => e.podcast_id !== id);
    return demoResponse({ success: true });
  }
  return apiFetch(`/podcasts/${id}`, { method: 'DELETE' });
}

// ============================================================
// EPISODES
// ============================================================

export async function fetchEpisodes(podcastId) {
  if (_demoMode) {
    let eps = _demoData.episodes;
    if (podcastId) eps = eps.filter(e => e.podcast_id === podcastId);
    eps.sort((a, b) => new Date(b.date) - new Date(a.date));
    return demoResponse(eps);
  }
  const query = podcastId ? `?podcast_id=${podcastId}` : '';
  return apiFetch(`/episodes${query}`);
}

export async function fetchEpisode(id) {
  if (_demoMode) {
    const ep = _demoData.episodes.find(e => e.id === id);
    if (!ep) throw new Error('Episode not found');
    return demoResponse(ep);
  }
  return apiFetch(`/episodes/${id}`);
}

// ============================================================
// ACTIONS
// ============================================================

export async function triggerScrape(podcastId) {
  if (_demoMode) {
    await delay(800);
    const pod = _demoData.podcasts.find(p => p.id === podcastId);
    if (pod) pod.last_scraped = new Date().toISOString();
    return demoResponse({ success: true, message: 'Scrape completed (demo)' });
  }
  return apiFetch(`/actions/scrape`, { method: 'POST', body: JSON.stringify({ podcast_id: podcastId }) });
}

export async function triggerTranscribe(episodeId) {
  if (_demoMode) {
    await delay(1200);
    const ep = _demoData.episodes.find(e => e.id === episodeId);
    if (ep && ep.status === 'new') {
      ep.status = 'transcribed';
      ep.transcript = 'Transcript generated in demo mode. In production, the audio would be processed by the transcription service and the full text would appear here. This placeholder represents what would be a complete word-for-word transcription of the podcast episode.';
    }
    return demoResponse({ success: true, message: 'Transcription completed (demo)' });
  }
  return apiFetch(`/actions/transcribe`, { method: 'POST', body: JSON.stringify({ episode_id: episodeId }) });
}

export async function triggerSummarize(episodeId) {
  if (_demoMode) {
    await delay(1000);
    const ep = _demoData.episodes.find(e => e.id === episodeId);
    if (ep && ep.status === 'transcribed') {
      ep.status = 'summarized';
      ep.summary = 'AI-generated summary produced in demo mode. In production, the LLM would analyse the transcript and produce a detailed editorial summary.';
      ep.gist = 'Brief one-line gist generated in demo mode.';
      ep.themes = ['Demo theme 1', 'Demo theme 2'];
      ep.key_quotes = [{ text: 'This is a demo quote from the episode.', speaker: 'Demo Speaker' }];
    }
    return demoResponse({ success: true, message: 'Summarization completed (demo)' });
  }
  return apiFetch(`/actions/summarize`, { method: 'POST', body: JSON.stringify({ episode_id: episodeId }) });
}

// ============================================================
// DISTRIBUTION LISTS
// ============================================================

export async function fetchDistributionLists() {
  if (_demoMode) return demoResponse(_demoData.distribution_lists);
  return apiFetch('/distribution');
}

export async function updateDistributionLists(data) {
  if (_demoMode) {
    Object.assign(_demoData.distribution_lists, data);
    return demoResponse(_demoData.distribution_lists);
  }
  return apiFetch('/distribution', { method: 'PUT', body: JSON.stringify(data) });
}

// ============================================================
// EMAIL
// ============================================================

export async function previewDailyEmail() {
  if (_demoMode) return demoResponse({ html: generateDailyEmailHTML() });
  return apiFetch('/email/daily/preview');
}

export async function previewWeeklyEmail() {
  if (_demoMode) return demoResponse({ html: generateWeeklyEmailHTML() });
  return apiFetch('/email/weekly/preview');
}

export async function sendDailyEmail() {
  if (_demoMode) {
    await delay(600);
    return demoResponse({ success: true, message: `Daily digest sent to ${_demoData.distribution_lists.daily.length} recipients (demo)` });
  }
  return apiFetch('/email/daily/send', { method: 'POST' });
}

export async function sendWeeklyEmail() {
  if (_demoMode) {
    await delay(600);
    return demoResponse({ success: true, message: `Weekly digest sent to ${_demoData.distribution_lists.weekly.length} recipients (demo)` });
  }
  return apiFetch('/email/weekly/send', { method: 'POST' });
}

// ============================================================
// CONFIG
// ============================================================

export async function fetchConfig() {
  if (_demoMode) return demoResponse(_demoData.config);
  return apiFetch('/config');
}

export async function updateConfig(data) {
  if (_demoMode) {
    Object.assign(_demoData.config, data);
    return demoResponse(_demoData.config);
  }
  return apiFetch('/config', { method: 'PUT', body: JSON.stringify(data) });
}

// ============================================================
// SEED DEMO DATA
// ============================================================

export async function seedDemoData() {
  if (_demoMode) {
    await delay(500);
    _demoData = JSON.parse(JSON.stringify(DEMO_DATA));
    return demoResponse({ success: true, message: 'Demo data seeded successfully' });
  }
  return apiFetch('/seed', { method: 'POST' });
}
